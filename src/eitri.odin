/*
Arguments are required.
Flags are optional and serve to modify the command's behavior.


Argument-exclusive tags:
- `variadic` :  int  = take all remaining arguments when set.


Flag-exclusive tags:
- `hidden`: bool = hide this flag from the usage documentation.
- `short`    :  byte = ascii character to represent the short version of a flag


Shared tags:
- `file`       :  string = for `os.Handle` types, file open mode.
- `perms`      :  string = for `os.Handle` types, file open permissions.
- `indistinct` :  bool   = allow the setting of distinct types by their base type.


Supported Data Types:
- bool
*/
package eitri


import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"


main :: proc() {
	Cmd_Build :: struct {
		arg:  struct {
			pkg: os.Handle,
		},
		flag: struct {
			output: string,
			debug:  bool,
		},
	}
	App_Mock :: struct {
		run: union {
			Cmd_Build,
		},
	}


	app := parse_app(new(App_Mock), os.args)
	switch cmd in app.run {
	case Cmd_Build:
		data := os.read_entire_file(cmd.arg.pkg) or_else unreachable()
		fmt.println(string(data))
		fmt.println(cmd.flag)
	}
}


parse_app :: proc(app: ^$T, raw_args: []string, allocator := context.allocator) -> ^T {
	cmd: runtime.Type_Info_Named
	{
		cmds := reflect.struct_field_by_name(T, "run")
		cmds_has_default_command := cmds.type.variant.(runtime.Type_Info_Union).no_nil
		if !cmds_has_default_command && len(raw_args) == 1 {
			crash("please specify a command")
		}
		raw_cmd := raw_args[1]
		defer if cmd == {} {
			crash(raw_cmd, "is an invalid command")
		}
		for c in cmds.type.variant.(runtime.Type_Info_Union).variants {
			cn := c.variant.(runtime.Type_Info_Named)
			if raw_cmd == strings.to_lower(strings.trim_left(cn.name, CMD_PREFIX)) {
				cmd = cn
				reflect.set_union_variant_type_info(reflect.struct_field_value(app^, cmds), c)
				break
			}
		}
	}
	args := reflect.struct_field_by_name(cmd.base.id, CMD_FIELD_NAME_ARG)
	flags := reflect.struct_field_by_name(cmd.base.id, CMD_FIELD_NAME_FLAG)
	arg_pos := 0
	defer {
		args_left := arg_pos - reflect.struct_field_count(args.type.id)
		if args_left != 0 {
			crash("missing arguments:", reflect.struct_field_names(args.type.id))
		}
	}
	for a in raw_args[2:] {
		target: reflect.Struct_Field
		if key, val, is_flag := parse_raw_arg_as_flag(a); is_flag {
			if strings.has_prefix(key, RAW_ARG_FLAG_PREFIX_SHORT) {
				unimplemented("short flags")
			}
			target = reflect.struct_field_by_name(flags.type.id, key)
			fmt.println(target)
			flags_ptr := rawptr(uintptr(app) + flags.offset)
			set_raw_arg(flags_ptr, target, val)
			continue
		}
		defer arg_pos += 1
		target = reflect.struct_field_at(args.type.id, arg_pos)
		args_ptr := rawptr(uintptr(app) + args.offset)
		set_raw_arg(args_ptr, target, a)
	}
	return app
}


parse_cmd :: proc(app: $T, cmd: string) {
	unimplemented()
}


set_raw_arg :: proc(model: rawptr, field: reflect.Struct_Field, arg: string) {
	field_ptr := uintptr(model) + field.offset
	switch field.type.id {
	case os.Handle:
		assert((os.is_file_path(arg) || os.is_dir_path(arg)), "invalid file path")
		field_ptr := cast(^os.Handle)field_ptr
		field_ptr^ = os.open(arg) or_else panic("cli: cannot open file")
	case bool:
		assert(arg == "")
		field_ptr := cast(^bool)field_ptr
		field_ptr^ = true
	}
}


/*
Parses a raw command-line argument assumed to be a flag.


Supports:
- Long flags (e.g., `--foo`, `--bar=value`)
- Short flags (e.g., `-a`, `-k=value`, or grouped like `-abc`)


- For flags using the `=` syntax (e.g., `--key=value`, `-k=value`), `key` will be the flag name and `val` the assigned value.
- Grouped short flags (e.g., `-abc`) are not split; the entire string (e.g., "-abc") is returned as `key`, and `val` is empty.
  To handle each flag individually in that case, use logic like:


    ```odin
    key, val := parse_raw_arg_as_flag(arg)
    if strings.has_prefix(key, "-") {
        for flag in key[1:] {
            do_something_with_short_flag(flag)
        }
    }
    ```


- For flags without `=`, `val` is an empty string.


Returns:
- key: the flag name or grouped short flags (raw, excluding prefix)
- val: the value assigned to the flag (if any); otherwise, an empty string
*/
parse_raw_arg_as_flag :: proc(
	arg: string,
	allocator := context.allocator,
) -> (
	key, val: string,
	is_flag: bool,
) {
	if strings.has_prefix(arg, RAW_ARG_FLAG_PREFIX_LONG) {
		is_flag = true
		kv := strings.split_n(
			strings.trim_left(arg, RAW_ARG_FLAG_PREFIX_LONG),
			RAW_ARG_FLAG_ASSIGNMENT_OPERATOR,
			2,
		)
		if len(kv[0]) == 0 {
			panic("flag name is empty")
		}
		key = kv[0]
		if len(kv) == 2 {
			val = kv[1]
		}
	} else if strings.has_prefix(arg, RAW_ARG_FLAG_PREFIX_SHORT) {
		is_flag = true
		kv := strings.split_n(
			strings.trim_left(arg, RAW_ARG_FLAG_PREFIX_SHORT),
			RAW_ARG_FLAG_ASSIGNMENT_OPERATOR,
			2,
		)
		if len(kv[0]) == 0 {
			panic("flag name is empty")
		}
		if len(kv) == 2 {
			if len(kv[0]) > 1 {
				fmt.panicf(
					"cannot assign on grouped short flags. separate the flag you want to assign a value to instead.",
				)
			}
			key = kv[0]
			if len(kv) == 2 {
				val = kv[1]
			}
		} else if len(kv) == 1 {
			key = arg
		} else {
			unreachable()
		}
	}
	return
}


// parse_cmd :: proc(model: ^any, raw_args: []string, allocator := context.allocator) {
// 	context.allocator = allocator
// 	id := typeid_of(type_of(model))
// 	fields := reflect.struct_fields_zipped(id)
//
//
// 	fields_arg := make(#soa[dynamic]reflect.Struct_Field)
// 	fields_flag := make(#soa[dynamic]reflect.Struct_Field)
// 	defer {
// 		delete(fields_arg)
// 		delete(fields_flag)
// 	}
// 	for f in fields {
// 		if strings.has_prefix(f.name, CMD_FIELD_PREFIX_ARG) {
// 			append(&fields_arg, f)
// 		} else if strings.has_prefix(f.name, CMD_FIELD_PREFIX_FLAG) {
// 			append(&fields_flag, f)
// 		} else {
// 			unimplemented("should i allow non-flag/arg fields?")
// 		}
// 	}
//
//
// 	flag_start: int
// 	set_args: for ra, i in raw_args {
// 		if !strings.has_prefix(ra, CMD_FIELD_PREFIX_FLAG) {
// 			flag_start = i
// 			break
// 		}
// 		name_val := strings.split_n(ra, RAW_ARG_FLAG_ASSIGNMENT_OPERATOR, 2)
// 		assert(len(name_val) > 0)
// 		name := name_val[0]
//
//
// 		flag_field: reflect.Struct_Field
// 		is_valid_flag: for f in fields_arg {
// 			if name == f.name {
// 				flag_field = f
// 				break
// 			}
// 		}
// 		if flag_field == {} {
// 			unimplemented("invalid flag. print help message")
// 		}
//
//
// 		flag_field_uptr := uintptr(model.(rawptr)) + flag_field.offset
// 		flag_field_type := flag_field.type
// 		is_bool_flag := len(name_val) == 1
// 		if is_bool_flag {
// 			_ =
// 				flag_field_type.variant.(runtime.Type_Info_Boolean) or_else panic(
// 					"flag requires an argument",
// 				)
// 			flag_field_bool := cast(^bool)flag_field_uptr
// 			flag_field_bool^ = true
// 		} else {
// 			assert(len(name_val) == 2)
// 			val := name_val[1]
// 			if val == "" {
// 				panic("missing flag value `--foo-flag=`")
// 			}
// 			// at this point, its okay if val is empty
// 			val = strings.trim(val, `"`)
// 			unimplemented()
// 		}
// 	}
// }


crash :: proc(args: ..any, sep := " ", exit_code := 1) {
	fmt.eprintln(..args, sep = sep)
	os.exit(exit_code)
}


crashf :: proc(format: string, args: ..any, exit_code := 1) {
	fmt.eprintfln(format, ..args)
	os.exit(exit_code)
}


// short flags are not supported
RAW_ARG_FLAG_PREFIX_LONG :: "--"
RAW_ARG_FLAG_PREFIX_SHORT :: "-"
RAW_ARG_FLAG_ASSIGNMENT_OPERATOR :: "="


APP_PREFIX :: "App_"
APP_FIELD_NAME_OF_ACTIVE_COMMAND :: "run"


CMD_PREFIX :: "Cmd_"
CMD_FIELD_NAME_ARG :: "arg"
CMD_FIELD_NAME_FLAG :: "flag"

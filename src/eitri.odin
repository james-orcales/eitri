/*
Arguments are required.
Flags are optional and serve to modify the command's behavior.


Argument-exclusive tags:
- `variadic` :  int  = take all remaining arguments when set. (default: 0)


Flag-exclusive tags:
- `hidden` :  bool = hide this flag from the usage documentation.
- `short`  :  byte = ascii character to represent the short version of a flag (default: first letter of field name)


Shared tags:
- `file`       :  string = for `os.Handle` types, file open mode. (default: <TODO>)
- `perms`      :  string = for `os.Handle` types, file open permissions. (default: <TODO>)
- `indistinct` :  bool   = allow the setting of distinct types by their base type.


Supported Data Types:
- bool
- byte
- string
- os.Handle
*/
package eitri


import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"


main :: proc() {
        Cmd_Meow :: struct {
                arg:  struct {
                        message: string,
                },
                flag: struct {
                        output:   os.Handle `eitri:"file=cw"`,
                        truncate: bool,
                },
        }
        App_Cat :: struct {
                run: union {
                        Cmd_Meow,
                },
        }


        app := app_init(new(App_Cat), os.args)
        fmt.println(app)
        switch cmd in app.run {
        case Cmd_Meow:
                out := cmd.flag.output == 0 ? os.stdout : cmd.flag.output
                if cmd.flag.truncate {
                        fmt.println("truncating..")
                        os.write_entire_file(
                                os.absolute_path_from_handle(out) or_else unreachable(),
                                transmute([]byte)cmd.arg.message,
                        )
                } else {
                        os.write_string(out, cmd.arg.message)
                }
        }
}


app_init :: proc(app: ^$T, raw_args: []string, allocator := context.allocator) -> ^T where intrinsics.type_is_named(T),
        intrinsics.type_is_struct(T),
        intrinsics.type_has_field(T, APP_FIELD_NAME_OF_ACTIVE_COMMAND) {


        raw_cmd := len(raw_args) > 1 ? raw_args[1] : ""
        variant := app_set_active_cmd(app, raw_cmd)
        cmd_init(&app.run, variant, raw_args[2:])
        return app
}


// TODO: initialize the value as well
app_set_active_cmd :: proc(app: ^$T, raw_cmd: string) -> (variant: typeid) where intrinsics.type_is_named(T),
        intrinsics.type_is_struct(T),
        intrinsics.type_has_field(T, APP_FIELD_NAME_OF_ACTIVE_COMMAND) {


        defer assert(variant != nil)
        active := reflect.struct_field_by_name(T, APP_FIELD_NAME_OF_ACTIVE_COMMAND)
        cmds :=
                runtime.type_info_base(active.type).variant.(runtime.Type_Info_Union) or_else panic(
                        "app struct's active cmd field must be a union type",
                )
        if raw_cmd == "" && !cmds.no_nil {
                crash("command not specified")
        }
        for c in cmds.variants {
                if name, _ := type_info_name_and_base(c); name != "" {
                        ensuref(
                                strings.has_prefix(name, CMD_PREFIX),
                                "command struct names must be prefixed with %s. got: %s",
                                CMD_PREFIX,
                                name,
                        )
                        if strings.to_lower(strings.trim_left(name, CMD_PREFIX)) != raw_cmd {
                                continue
                        }
                        reflect.set_union_variant_type_info(reflect.struct_field_value(app^, active), c)
                        return c.id
                }
                panicf("a command must be a named struct. got an anonymous struct: %T", c)
        }
        if !cmds.no_nil {
                crash(raw_cmd, "is an invalid command")
        }
        return nil
}


cmd_init :: proc(cmd: rawptr, type: typeid, positional_args_and_flags: []string) {
        ensuref(reflect.is_struct(type_info_of(type)), "command %s must be a struct", type)
        args := reflect.struct_field_by_name(type, CMD_FIELD_NAME_ARG)
        flags := reflect.struct_field_by_name(type, CMD_FIELD_NAME_FLAG)
        arg_pos := 0
        seen_end_of_options_marker := false
        defer {
                args_left := arg_pos - reflect.struct_field_count(args.type.id)
                if args_left != 0 {
                        crash("missing arguments:", reflect.struct_field_names(args.type.id))
                }
        }
        for a in positional_args_and_flags {
                if !seen_end_of_options_marker {
                        if a == END_OF_OPTIONS_MARKER {
                                if arg_pos > 0 {
                                        crashf(
                                                "positional arguments are not allowed before the end of options marker `--`. got: %s",
                                                a,
                                        )
                                }
                                seen_end_of_options_marker = true
                                continue
                        }
                        if k, v, is_flag := raw_arg_parse_as_flag(a); is_flag {
                                is_grouped_flags :=
                                        strings.has_prefix(k, RAW_ARG_FLAG_PREFIX_SHORT) &&
                                        !strings.has_prefix(k, RAW_ARG_FLAG_PREFIX_LONG)
                                if is_grouped_flags {
                                        unimplemented()
                                }
                                flag := reflect.struct_field_by_name(flags.type.id, k)
                                raw_arg_to_typed_value(
                                        uintptr(cmd) + flags.offset + flag.offset,
                                        flag.type.id,
                                        v,
                                        options_init_from_struct_tag(flag.tag),
                                )
                                continue
                        }
                }
                defer arg_pos += 1
                arg := reflect.struct_field_at(args.type.id, arg_pos)
                raw_arg_to_typed_value(
                        uintptr(cmd) + args.offset + arg.offset,
                        arg.type.id,
                        a,
                        options_init_from_struct_tag(arg.tag),
                )
        }
}


/*
- `variadic` :  int  = take all remaining arguments when set. (default: 0)


- `hidden` :  bool = hide this flag from the usage documentation.
- `short`  :  byte = ascii character to represent the short version of a flag (default: first letter of field name)


- `file`       :  string = for `os.Handle` types, file open mode. (default: <TODO>)
- `perms`      :  string = for `os.Handle` types, file open permissions. (default: <TODO>)
- `indistinct` :  bool   = allow the setting of distinct types by their base type.
*/
Option :: struct {
        tag:  Option_Enum,
        data: Option_Type,
}
Option_Enum :: enum {
        // Argument-exclusive tags
        variadic,


        // Flag-exclusive tags
        hidden,
        short,


        // Shared tags:
        file,
        perms,
        indistinct,
}
Option_Type :: struct #raw_union {
        bool:   bool,
        byte:   byte,
        int:    int,
        string: string,
}


// caller owns the returned options
options_init_from_struct_tag :: proc(tags: reflect.Struct_Tag, allocator := context.allocator) -> []Option {
        context.allocator = allocator
        options := make([dynamic]Option)
        for kv in strings.split(reflect.struct_tag_get(tags, STRUCT_TAG_KEY), ",") {
                k, v := strings_split_in_two(kv, "=")
                o := Option {
                        tag = reflect.enum_from_name(Option_Enum, k) or_continue,
                }
                defer append(&options, o)
                value_is_unspecified := v == ""
                switch o.tag {
                case .hidden, .indistinct:
                        ensuref(value_is_unspecified, "tag %s does not take a value. got: %s", o.tag, v)
                        o.data.bool = true
                case .variadic:
                        o.data.int = strconv.atoi(v)


                // this doesnt even get set to default if file mode is set
                case .perms:
                        perms, ok := strconv.parse_int(v, 8)
                        ensure(len(v) == 3 && ok, "perms tag value must be an octal integer. default=444")
                        // BUG: fix perms if file mode is set already. i set it temporarily to 644 for testing
                        o.data.int = perms == 0 ? 0o644 : perms
                        fmt.println("bro", o.data.int)
                case .short:
                        ensuref(len(v) == 1, "short tag value must be an ascii character")
                        o.data.byte = v[0]
                case .file:
                        mode := os.O_RDONLY
                        if !value_is_unspecified {
                                can_read, can_write := strings.contains(v, "r"), strings.contains(v, "w")
                                mode =
                                        can_read && can_write ? os.O_RDWR : can_write && !can_read ? os.O_WRONLY : os.O_RDONLY
                                mode |= strings.contains(v, "c") ? os.O_CREATE : 0
                                mode |= strings.contains(v, "a") ? os.O_APPEND : 0
                                mode |= strings.contains(v, "t") ? os.O_TRUNC : 0
                        }
                        o.data.int = mode
                }
        }
        return options[:]
}


raw_arg_to_typed_value :: proc(var: uintptr, type: typeid, arg: string, options: []Option) {
        options_lookup :: proc(options: []Option, tag: Option_Enum) -> Option_Type {
                for o in options {
                        if o.tag == tag {
                                return o.data
                        }
                }
                return Option_Type{}
        }
        switch type {
        case os.Handle:
                var := cast(^os.Handle)var
                flags := options_lookup(options, .file).int
                // mode := options_lookup(options, .perms).int
                handle, err := os.open(arg, flags, 0o644)
                if err != nil {
                        crashf("cannot open %s: %v", arg, err)
                }
                var^ = handle
        case bool:
                assert(arg == "")
                var := cast(^bool)var
                var^ = true
        case string:
                var := cast(^string)var
                var^ = arg
        case byte:
                ensure(len(arg) == 1)
                var := cast(^byte)var
                var^ = arg[0]
        case:
                unimplemented()
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
raw_arg_parse_as_flag :: proc(arg: string, allocator := context.allocator) -> (key, val: string, is_flag: bool) {
        if strings.has_prefix(arg, RAW_ARG_FLAG_PREFIX_LONG) {
                is_flag = true
                key, val = strings_split_in_two(
                        strings.trim_left(arg, RAW_ARG_FLAG_PREFIX_SHORT),
                        RAW_ARG_FLAG_ASSIGNMENT_OPERATOR,
                )
                ensure(key != "", "flag name is empty")
        } else if strings.has_prefix(arg, RAW_ARG_FLAG_PREFIX_SHORT) {
                is_flag = true
                key, val = strings_split_in_two(
                        strings.trim_left(arg, RAW_ARG_FLAG_PREFIX_SHORT),
                        RAW_ARG_FLAG_ASSIGNMENT_OPERATOR,
                )
                ensure(key != "", "flag name is empty")
                if val != "" {
                        if len(key) > 1 {
                                fmt.panicf(
                                        "cannot assign on grouped short flags. separate the flag you want to assign a value to instead.",
                                )
                        }
                } else if val == "" {
                        key = arg
                } else {
                        unreachable()
                }
        }
        return
}


type_info_name_and_base :: proc(type: ^runtime.Type_Info) -> (name: string, base: ^runtime.Type_Info) {
        type, ok := type.variant.(runtime.Type_Info_Named)
        if !ok {
                return
        }
        return type.name, runtime.type_info_base(type.base)
}


strings_split_in_two :: proc(s, sep: string, allocator := context.allocator) -> (before, after: string) {
        bf := strings.split_n(s, sep, 2, allocator)
        before = bf[0]
        if len(bf) == 2 {
                after = bf[1]
        }
        return
}


STRUCT_TAG_KEY :: "eitri"
END_OF_OPTIONS_MARKER :: "--"


// short flags are not supported
RAW_ARG_FLAG_PREFIX_LONG :: "--"
RAW_ARG_FLAG_PREFIX_SHORT :: "-"
RAW_ARG_FLAG_ASSIGNMENT_OPERATOR :: "="


APP_PREFIX :: "App_"
APP_FIELD_NAME_OF_ACTIVE_COMMAND :: "run"


CMD_PREFIX :: "Cmd_"
CMD_FIELD_NAME_ARG :: "arg"
CMD_FIELD_NAME_FLAG :: "flag"

package eitri


import "core:fmt"
import "core:os"


ASSERT_MESSAGE_FORMAT_STR :: "eitri: %s"


@(cold)
panic :: proc(message: string, loc := #caller_location) -> ! {
        fmt.panicf(ASSERT_MESSAGE_FORMAT_STR, message, loc = loc)
}


@(cold)
panicf :: proc(format: string, args: ..any, loc := #caller_location) -> ! {
        fmt.panicf(fmt.tprintf(ASSERT_MESSAGE_FORMAT_STR, format), ..args, loc = loc)
}


@(disabled = ODIN_DISABLE_ASSERT)
assert :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) {
        fmt.assertf(condition, ASSERT_MESSAGE_FORMAT_STR, message, loc = loc)
}


@(disabled = ODIN_DISABLE_ASSERT)
assertf :: proc(condition: bool, format: string, args: ..any, loc := #caller_location) {
        fmt.assertf(condition, fmt.tprintf(ASSERT_MESSAGE_FORMAT_STR, format), ..args, loc = loc)
}


ensure :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) {
        fmt.ensuref(condition, ASSERT_MESSAGE_FORMAT_STR, message, loc = loc)
}


ensuref :: proc(condition: bool, format: string, args: ..any, loc := #caller_location) {
        fmt.ensuref(condition, fmt.tprintf(ASSERT_MESSAGE_FORMAT_STR, format), ..args, loc = loc)
}


@(cold)
crash :: proc(args: ..any, sep := " ", exit_code := 1) -> ! {
        fmt.eprintln(..args, sep = sep)
        os.exit(exit_code)
}


@(cold)
crashf :: proc(format: string, args: ..any, exit_code := 1) -> ! {
        fmt.eprintfln(format, ..args)
        os.exit(exit_code)
}

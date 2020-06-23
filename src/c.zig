// TODO: We only use one function from libc. I'm sure Zig will get it
//       to it's std in the future, so look out for that
pub usingnamespace @cImport({
    @cInclude("sys/ioctl.h");
});

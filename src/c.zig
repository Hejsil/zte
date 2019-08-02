// TODO: We only use two functions from libc. I'm sure Zig will get them
//       (or at least ioctl) to it's std in the future, so look out for
//       that
pub usingnamespace @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("termios.h");
});

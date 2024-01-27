pub mod raw {
    #[no_mangle]
    extern "C" {
        pub fn os_ClrHome();
        pub fn os_EnableCursor();
        pub fn os_DisableCursor();
        pub fn os_SetCursorPos(curRow: u8, curCol: u8);
        pub fn os_PutStrFull(s: *const core::ffi::c_char);
    }
}
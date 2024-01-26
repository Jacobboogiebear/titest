#![no_std]
#![no_main]

mod ti;

#[no_mangle]
extern "C" fn main() {
	let v = "Hello\0".as_ptr().cast::<core::ffi::c_char>();
	unsafe {
		ti::os_ClrHome();
		ti::os_SetCursorPos(1, 1);
		ti::os_PutStrFull(v);
	}
	loop {};
}


use core::panic::PanicInfo;
#[allow(unconditional_recursion)]
#[panic_handler]
fn panic_handler_phony(info: &PanicInfo) -> ! { panic_handler_phony(info) }


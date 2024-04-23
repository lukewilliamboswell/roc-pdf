use core::ffi::c_void;
use lopdf::content::{Content, Operation};
use lopdf::dictionary;
use lopdf::{Document, Object, ObjectId, Stream};
use roc_std::{RocResult, RocStr};
use std::cell::RefCell;
use std::{alloc::Layout, mem::MaybeUninit, sync::Mutex};

pub static DOCUMENT: Mutex<RefCell<Option<PdfDocument>>> = Mutex::new(RefCell::new(None));

#[derive(Debug)]
pub struct PdfDocument {
    doc: Document,

    #[allow(dead_code)]
    pages_id: ObjectId,
}

impl PdfDocument {
    fn new() -> Self {
        let mut doc = Document::with_version("1.5");
        let pages_id = doc.new_object_id();

        let font_id = doc.add_object(dictionary! {
            // type of dictionary
            "Type" => "Font",
            // type of font, type1 is simple postscript font
            "Subtype" => "Type1",
            // basefont is postscript name of font for type1 font.
            // See PDF reference document for more details
            "BaseFont" => "Courier",
        });

        // font dictionaries need to be added into resource dictionaries
        // in order to be used.
        // Resource dictionaries can contain more than just fonts,
        // but normally just contains fonts
        // Only one resource dictionary is allowed per page tree root
        let resources_id = doc.add_object(dictionary! {
            // fonts are actually triplely nested dictionaries. Fun!
            "Font" => dictionary! {
                // F1 is the font name used when writing text.
                // It must be unique in the document. It does not
                // have to be F1
                "F1" => font_id,
            },
        });

        // Content is a wrapper struct around an operations struct that contains a vector of operations
        // The operations struct contains a vector of operations that match up with a particular PDF
        // operator and operands.
        // Reference the PDF reference for more details on these operators and operands.
        // Note, the operators and operands are specified in a reverse order than they
        // actually appear in the PDF file itself.
        let content = Content {
            operations: vec![
                // BT begins a text element. it takes no operands
                Operation::new("BT", vec![]),
                // Tf specifies the font and font size. Font scaling is complicated in PDFs. Reference
                // the reference for more info.
                // The into() methods are defined based on their paired .from() methods (this
                // functionality is built into rust), and are converting the provided values into
                // An enum that represents the basic object types in PDF documents.
                Operation::new("Tf", vec!["F1".into(), 48.into()]),
                // Td adjusts the translation components of the text matrix. When used for the first
                // time after BT, it sets the initial text position on the page.
                // Note: PDF documents have Y=0 at the bottom. Thus 600 to print text near the top.
                Operation::new("Td", vec![100.into(), 600.into()]),
                // Tj prints a string literal to the page. By default, this is black text that is
                // filled in. There are other operators that can produce various textual effects and
                // colors
                Operation::new("Tj", vec![Object::string_literal("Hello World!")]),
                // ET ends the text element
                Operation::new("ET", vec![]),
            ],
        };

        // Streams are a dictionary followed by a sequence of bytes. What that sequence of bytes
        // represents depends on context
        // The stream dictionary is set internally to lopdf and normally doesn't
        // need to be manually manipulated. It contains keys such as
        // Length, Filter, DecodeParams, etc
        //
        // content is a stream of encoded content data.
        let content_id = doc.add_object(Stream::new(dictionary! {}, content.encode().unwrap()));

        // Page is a dictionary that represents one page of a PDF file.
        // It has a type, parent and contents
        let page_id = doc.add_object(dictionary! {
            "Type" => "Page",
            "Parent" => pages_id,
            "Contents" => content_id,
        });

        // Again, pages is the root of the page tree. The ID was already created
        // at the top of the page, since we needed it to assign to the parent element of the page
        // dictionary
        //
        // This is just the basic requirements for a page tree root object. There are also many
        // additional entries that can be added to the dictionary if needed. Some of these can also be
        // defined on the page dictionary itself, and not inherited from the page tree root.
        let pages = dictionary! {
            // Type of dictionary
            "Type" => "Pages",
            // Vector of page IDs in document. Normally would contain more than one ID and be produced
            // using a loop of some kind
            "Kids" => vec![page_id.into()],
            // Page count
            "Count" => 1,
            // ID of resources dictionary, defined earlier
            "Resources" => resources_id,
            // a rectangle that defines the boundaries of the physical or digital media. This is the
            // "Page Size"
            "MediaBox" => vec![0.into(), 0.into(), 595.into(), 842.into()],
        };

        // using insert() here, instead of add_object() since the id is already known.
        doc.objects.insert(pages_id, Object::Dictionary(pages));

        // Creating document catalog.
        // There are many more entries allowed in the catalog dictionary.
        let catalog_id = doc.add_object(dictionary! {
            "Type" => "Catalog",
            "Pages" => pages_id,
        });

        // Root key in trailer is set here to ID of document catalog,
        // remainder of trailer is set during doc.save().
        doc.trailer.set("Root", catalog_id);

        PdfDocument { doc, pages_id }
    }
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    libc::free(c_ptr)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: *mut RocStr, tag_id: u32) {
    match tag_id {
        0 => {
            eprintln!("Roc standard library hit a panic: {}", &*msg);
        }
        1 => {
            eprintln!("Application hit a panic: {}", &*msg);
        }
        _ => unreachable!(),
    }
    std::process::exit(1);
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: *mut RocStr, msg: *mut RocStr, src: *mut RocStr) {
    eprintln!("[{}] {} = {}", &*loc, &*src, &*msg);
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_mmap(
    addr: *mut libc::c_void,
    len: libc::size_t,
    prot: libc::c_int,
    flags: libc::c_int,
    fd: libc::c_int,
    offset: libc::off_t,
) -> *mut libc::c_void {
    libc::mmap(addr, len, prot, flags, fd, offset)
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_shm_open(
    name: *const libc::c_char,
    oflag: libc::c_int,
    mode: libc::mode_t,
) -> libc::c_int {
    libc::shm_open(name, oflag, mode as libc::c_uint)
}

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    pub fn roc_main(output: *mut u8);

    #[link_name = "roc__mainForHost_1_exposed_size"]
    pub fn roc_main_size() -> i64;

    #[link_name = "roc__mainForHost_0_caller"]
    fn call_Fx(flags: *const u8, closure_data: *const u8, output: *mut RocResult<(), i32>);

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_size"]
    fn size_Fx() -> i64;

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_result_size"]
    fn size_Fx_result() -> i64;
}

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    init();
    let size = unsafe { roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        roc_main(buffer);

        let out = call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);

        out
    }
}

/// # Safety
///
/// TODO
pub unsafe fn call_the_closure(closure_data_ptr: *const u8) -> i32 {
    // Main always returns an i32. just allocate for that.
    let mut out: RocResult<(), i32> = RocResult::ok(());

    call_Fx(
        // This flags pointer will never get dereferenced
        MaybeUninit::uninit().as_ptr(),
        closure_data_ptr,
        &mut out,
    );

    match out.into() {
        Ok(()) => 0,
        Err(exit_code) => exit_code,
    }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    {
        let mut doc_guard = DOCUMENT.lock().unwrap();
        match doc_guard.get_mut() {
            Some(pdf) => {
                dbg!(pdf);
                panic!("expected document to be empty")
            }
            None => doc_guard.replace(Some(PdfDocument::new())),
        };
    }

    init();

    rust_main()
}

// Protect our functions from the vicious GC.
// This is specifically a problem with static compilation and musl.
// TODO: remove all of this when we switch to effect interpreter.
pub fn init() {
    let funcs: &[*const extern "C" fn()] = &[roc_fx_save as _];
    #[allow(forgetting_references)]
    std::mem::forget(std::hint::black_box(funcs));
    if cfg!(unix) {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        #[allow(forgetting_references)]
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_save(path: RocStr) -> RocResult<(), RocStr> {
    let mut doc_guard = DOCUMENT.lock().unwrap();

    match doc_guard.get_mut() {
        None => RocResult::err(RocStr::from("DOCUMENT NOT FOUND")),
        Some(pdf) => {
            pdf.doc.compress();
            match pdf.doc.save(path.as_str()) {
                Ok(..) => RocResult::ok(()),
                Err(..) => RocResult::err(RocStr::from("ERROR SAVING DOCUMENT")),
            }
        }
    }
}

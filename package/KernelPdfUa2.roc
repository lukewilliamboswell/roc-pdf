# Inspect exact tagged-PDF objects after the shared typed structure, navigation
# and archival validators. The facade calls this only for accessibility
# claims. The catalog and page dictionaries are visited with scalar cursors;
# neither an auxiliary index nor a copy of the object store is needed.
import KernelLex
import KernelObject
import KernelSeal
import unicode.ByteRange
import unicode.Scalar

KernelPdfUa2 :: [].{
	Requirement : [DisplayTitle, DocumentLanguage, Marked, PageTabs, StructureRoot]
	Violation : { position : U64, requirement : Requirement }

	clause : Requirement -> Str
	clause = |requirement| match requirement {
		Marked => "ISO 14289-2:2024 6.2"
		StructureRoot => "ISO 14289-2:2024 8.2.5.2"
		DocumentLanguage => "ISO 14289-2:2024 8.4.4"
		PageTabs => "ISO 14289-2:2024 8.9.3.3"
		DisplayTitle => "ISO 14289-2:2024 8.11.2"
	}

	requirement_code : Requirement -> Str
	requirement_code = |requirement| match requirement {
		Marked => "ROC-PDF-PDFUA2-6-2-MARK-INFO"
		StructureRoot => "ROC-PDF-PDFUA2-8-2-5-2-DOCUMENT-ROOT"
		DocumentLanguage => "ROC-PDF-PDFUA2-8-4-4-DEFAULT-LANGUAGE"
		PageTabs => "ROC-PDF-PDFUA2-8-9-3-3-PAGE-TABS"
		DisplayTitle => "ROC-PDF-PDFUA2-8-11-2-DISPLAY-DOC-TITLE"
	}

	summary : Requirement -> Str
	summary = |requirement| match requirement {
		Marked => "the catalog must mark the document as tagged"
		StructureRoot => "the structure tree must have a single PDF 2.0 Document child"
		DocumentLanguage => "the catalog must carry a nonempty document language"
		PageTabs => "each page with annotations must use structure order for keyboard navigation"
		DisplayTitle => "the catalog must tell readers to display the document title"
	}

	validate_lowered : KernelSeal.Plan, KernelObject.ObjectId -> Try({}, Violation)
	validate_lowered = |sealed, root| {
		store = KernelSeal.Plan.store(sealed)
		position = KernelObject.ObjectId.number(root) - 1
		catalog = object_value(store, root)
		mark_info = field(store, catalog, mark_info_key)
		if !value_true(field(store, mark_info, marked_key)) {
			return Err({ position, requirement: Marked })
		}
		tree = dereference(store, field(store, catalog, structure_root_name))
		document_value = field(store, tree, kids_key)
		document = dereference(store, document_value)
		namespace = dereference(store, field(store, document, namespace_key))
		if !named(store, field(store, tree, type_key), structure_root_name)
			or !named(store, field(store, document, s_name), document_name)
			or text_bytes(store, field(store, namespace, namespace_key)) != standard_namespace {
			return Err({ position, requirement: StructureRoot })
		}
		if text_bytes(store, field(store, catalog, language_key)).is_empty() {
			return Err({ position, requirement: DocumentLanguage })
		}
		viewer = field(store, catalog, viewer_preferences_key)
		if !value_true(field(store, viewer, display_title_key)) {
			return Err({ position, requirement: DisplayTitle })
		}
		var $page = 0
		for object in store.objects {
			value = stored_value(store, object.content)
			if named(store, field(store, value, type_key), page_name) {
				if array_present(field(store, value, annotations_key)) and !named(store, field(store, value, tabs_key), s_name) {
					return Err({ position: $page, requirement: PageTabs })
				}
				$page = $page + 1
			}
		}
		Ok({})
	}

	## Public authored strings that become human-readable PDF text strings
	## cannot contain Private Use Area scalars. Iterate UTF-8 without retaining
	## a scalar list and report the original byte offset of the first one.
	private_use_offset : Str -> [NoPrivateUse, PrivateUse(U64)]
	private_use_offset = |value| {
		for located in Scalar.iter(value) {
			scalar = Scalar.to_u32(located.scalar)
			if (scalar >= 0xE000 and scalar <= 0xF8FF) or (scalar >= 0xF0000 and scalar <= 0xFFFFD) or (scalar >= 0x100000 and scalar <= 0x10FFFD) {
				return PrivateUse(ByteRange.start(located.byte_range))
			}
		}
		NoPrivateUse
	}
}

object_value : KernelObject.Store, KernelObject.ObjectId -> KernelObject.Value
object_value = |store, id| stored_value(store, list_at(store.objects, KernelObject.ObjectId.number(id) - 1).content)

stored_value : KernelObject.Store, KernelObject.ObjectContent -> KernelObject.Value
stored_value = |store, content| match content {
	Stored(value) => list_at(store.values, KernelObject.ValueId.index(value))
	LengthOf(_) => Null
}

dereference : KernelObject.Store, KernelObject.Value -> KernelObject.Value
dereference = |store, value| match value {
	Reference(id) => object_value(store, id)
	_ => Null
}

text_bytes : KernelObject.Store, KernelObject.Value -> List(U8)
text_bytes = |store, value| match value {
	TextString(id) => KernelLex.Text.bytes(list_at(store.text_strings, KernelObject.TextStringId.index(id)))
	_ => []
}

value_true : KernelObject.Value -> Bool
value_true = |value| match value {
	Boolean(True) => True
	_ => False
}

array_present : KernelObject.Value -> Bool
array_present = |value| match value {
	Array({ length, .. }) => length > 0
	_ => False
}

named : KernelObject.Store, KernelObject.Value, List(U8) -> Bool
named = |store, value, name| match value {
	Name(id) => KernelLex.Name.bytes(list_at(store.names, KernelObject.NameId.index(id))) == name
	_ => False
}

field : KernelObject.Store, KernelObject.Value, List(U8) -> KernelObject.Value
field = |store, value, key_bytes| {
	span = match value {
		Dictionary(entries) => entries
		_ => return Null
	}
	var $index = span.start
	while $index < span.start + span.length {
		entry = list_at(store.dictionary_entries, $index)
		if KernelLex.Name.bytes(list_at(store.names, KernelObject.NameId.index(entry.key))) == key_bytes {
			return list_at(store.values, KernelObject.ValueId.index(entry.value))
		}
		$index = $index + 1
	}
	Null
}

list_at : List(a), U64 -> a
list_at = |list, index| list.get(index) ?? crash "accessibility check escaped the sealed object store"

mark_info_key : List(U8)
mark_info_key = Str.to_utf8("MarkInfo")

marked_key : List(U8)
marked_key = Str.to_utf8("Marked")

structure_root_name : List(U8)
structure_root_name = Str.to_utf8("StructTreeRoot")

kids_key : List(U8)
kids_key = Str.to_utf8("K")

namespace_key : List(U8)
namespace_key = Str.to_utf8("NS")

type_key : List(U8)
type_key = Str.to_utf8("Type")

s_name : List(U8)
s_name = Str.to_utf8("S")

document_name : List(U8)
document_name = Str.to_utf8("Document")

language_key : List(U8)
language_key = Str.to_utf8("Lang")

viewer_preferences_key : List(U8)
viewer_preferences_key = Str.to_utf8("ViewerPreferences")

display_title_key : List(U8)
display_title_key = Str.to_utf8("DisplayDocTitle")

page_name : List(U8)
page_name = Str.to_utf8("Page")

annotations_key : List(U8)
annotations_key = Str.to_utf8("Annots")

tabs_key : List(U8)
tabs_key = Str.to_utf8("Tabs")

standard_namespace : List(U8)
standard_namespace = Str.to_utf8("http://iso.org/pdf2/ssn")

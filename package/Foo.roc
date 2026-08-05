Foo :: {}.{

	## A temporary value used while the PDF API is being designed.
	placeholder : Str
	placeholder = "foo"

	## A minimal PDF 2.0 document used to exercise the test harness.
	placeholder_pdf : U64 -> List(U8)
	placeholder_pdf = |percent_offset| {
		bytes = Str.to_utf8("%PDF-2.0\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> >>\nendobj\n4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000219 00000 n \ntrailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n268\n%%EOF\n")
		match List.set(bytes, percent_offset, 37) {
			Ok(pdf) => pdf
			Err(_) => []
		}
	}
}

## The temporary harness value remains stable until the facade replaces it.
expect Foo.placeholder == "foo"

## The temporary harness PDF retains its exact snapshot size.
expect Foo.placeholder_pdf(0).len() == 431

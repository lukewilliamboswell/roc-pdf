import "../vendor/fonts/Inter-4.1-Regular.ttf" as inter : List(U8)
import pdf.Font
import pdf.KernelDeflate
import pdf.KernelSha256
import pdf.KernelSrgbProfile

## Single-kernel workloads for `allocation_profile`, measured on their own so
## a change inside one kernel shows up without a whole document around it.
## Only `run` is measured. `input` takes a runtime `seed` (always 1 in the
## profile) so the input is not a compile-time constant the compiler could
## evaluate ahead of time.
ProfileKernels :: [].{
	Kernel : { name : Str, input : U64 -> List(U8), run : List(U8) -> U64 }

	all : List(Kernel)
	all = [
		{ name: "deflate_icc", input: icc, run: |input| deflate(input, KernelDeflate.Level.balanced) },
		{ name: "deflate_content", input: content, run: |input| deflate(input, KernelDeflate.Level.balanced) },
		{ name: "sha256_content", input: content, run: sha256 },
		{ name: "register_inter", input: |seed| inter.take_first(inter.len() + 1 - seed), run: register },
		{ name: "deflate_content_fastest", input: content, run: |input| deflate(input, KernelDeflate.Level.fastest) },
		{ name: "deflate_content_smallest", input: content, run: |input| deflate(input, KernelDeflate.Level.smallest) },
	]
}

icc : U64 -> List(U8)
icc = |seed| KernelSrgbProfile.bytes.take_first(KernelSrgbProfile.bytes.len() + 1 - seed)

## A text-heavy content stream of about 4 KiB, the shape most PDF streams have.
content : U64 -> List(U8)
content = |seed| {
	var $bytes = List.with_capacity(4096)
	var $line = 0
	while $line < 80 {
		for byte in Str.iter_utf8("BT /F1 11 Tf 50 ${(700 - $line * seed * 8).to_str()} Td [<0001> -3 <0002>] TJ ET\n") {
			$bytes = $bytes.append(byte)
		}
		$line = $line + 1
	}
	$bytes
}

## `deflate_icc` and `deflate_content` compress at the package default level;
## the `_fastest` and `_smallest` kernels measure the other two levels.
deflate : List(U8), KernelDeflate.Level -> U64
deflate = |input, level| {
	limits = KernelDeflate.Limits.make({ max_input_bytes: 16777216, max_output_bytes: 16777216 })
	match KernelDeflate.Plan.prepare(input, level, limits) {
		Err(_) => crash "deflate prepare failed"
		Ok(plan) => match KernelDeflate.to_bytes(plan) {
			Err(_) => crash "deflate failed"
			Ok(result) => result.bytes.len()
		}
	}
}

sha256 : List(U8) -> U64
sha256 = |input| match KernelSha256.digest(input) {
	Err(_) => crash "digest failed"
	Ok(digest) => digest.len()
}

register : List(U8) -> U64
register = |bytes| match Font.Registry.empty.register({ bytes: bytes, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: Font.ValidationLimits.default }) {
	Err(_) => crash "registration failed"
	Ok(_) => bytes.len()
}

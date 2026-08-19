import pdf.KernelEmit
import pdf.KernelStructure
import pdf.KernelUnicode

## Project-owned seam vectors for the facts passed from the pinned Unicode
## package into source, line-layout, and font-selection stages. These are
## deliberately compact representatives of the official Unicode 17.0.0 test
## data, not a copied replacement for unicode's complete conformance corpus.
Fixture :: [].{
	VectorError : [
		GraphemeVectorMismatch,
		LineVectorMismatch,
		MissingAtomicLimitRejection,
		Unicode(KernelUnicode.UnicodeError),
		EvidenceFailure,
	]

	uax_boundary_vectors : U64 -> Try({ bytes : List(U8), work : List(U64) }, VectorError)
	uax_boundary_vectors = |runtime_context| {

		## Retain an explicit runtime context so test-application failure is a
		## normal typed result, never a compile-time-known match.
		if runtime_context > 1 {
			return Err(EvidenceFailure)
		}
		crlf = KernelUnicode.analyze("\r\n", limits(2, 3)) ? Unicode
		devanagari_conjunct = KernelUnicode.analyze("क्क", limits(3, 4)) ? Unicode
		ak_ri = KernelUnicode.analyze("ଅ🇦", limits(2, 3)) ? Unicode
		ai_space_ri = KernelUnicode.analyze("❗ 🇦", limits(3, 4)) ? Unicode
		if crlf.graphemes != [{ byte_start: 0, byte_end: 2, scalar_start: 0, scalar_end: 2 }] or devanagari_conjunct.graphemes != [{ byte_start: 0, byte_end: 9, scalar_start: 0, scalar_end: 3 }] {
			return Err(GraphemeVectorMismatch)
		}

		## UAX #14 rev. 55 LineBreakTest-17.0.0 vectors: AI+SP+RI and AK+RI.
		## Start and final positions are retained as Prohibited/Mandatory facts by
		## the project boundary even though the official notation only marks breaks.
		if !lines_equal(
			ak_ri.line_boundaries,
			[
				{ byte_offset: 0, scalar_offset: 0, decision: Prohibited },
				{ byte_offset: 3, scalar_offset: 1, decision: Allowed },
				{ byte_offset: 7, scalar_offset: 2, decision: Mandatory },
			],
		) or !lines_equal(
			ai_space_ri.line_boundaries,
			[
				{ byte_offset: 0, scalar_offset: 0, decision: Prohibited },
				{ byte_offset: 3, scalar_offset: 1, decision: Prohibited },
				{ byte_offset: 4, scalar_offset: 2, decision: Allowed },
				{ byte_offset: 8, scalar_offset: 3, decision: Mandatory },
			],
		) {
			return Err(LineVectorMismatch)
		}

		## UAX #29 rev. 47's GB3 CR × LF and GB9c Indic conjunct vectors must
		## remain one source-relative grapheme each; they must not be reconstructed
		## from later glyph data.
		plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
		Ok({
			bytes,
			work: [
				4,
				26,
				crlf.work.scalar_visits + devanagari_conjunct.work.scalar_visits + ak_ri.work.scalar_visits + ai_space_ri.work.scalar_visits,
				crlf.work.grapheme_visits + devanagari_conjunct.work.grapheme_visits + ak_ri.work.grapheme_visits + ai_space_ri.work.grapheme_visits,
				crlf.work.line_boundary_visits + devanagari_conjunct.work.line_boundary_visits + ak_ri.work.line_boundary_visits + ai_space_ri.work.line_boundary_visits,
				crlf.work.script_run_visits + devanagari_conjunct.work.script_run_visits + ak_ri.work.script_run_visits + ai_space_ri.work.script_run_visits,
				crlf.graphemes.len(),
				devanagari_conjunct.graphemes.len(),
				ak_ri.line_boundaries.len(),
				ai_space_ri.line_boundaries.len(),
				line_decision_code(ak_ri.line_boundaries, 0),
				line_decision_code(ak_ri.line_boundaries, 1),
				line_decision_code(ak_ri.line_boundaries, 2),
				line_decision_code(ai_space_ri.line_boundaries, 0),
				line_decision_code(ai_space_ri.line_boundaries, 1),
				line_decision_code(ai_space_ri.line_boundaries, 2),
				line_decision_code(ai_space_ri.line_boundaries, 3),
			],
		})
	}

	atomic_limit_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, VectorError)
	atomic_limit_negatives = |runtime_context| {
		if runtime_context != 1 {
			return Err(EvidenceFailure)
		}
		grapheme_limit = match KernelUnicode.analyze("\r\n", { ..limits(2, 3), max_graphemes: runtime_context - 1 }) {
			Err(GraphemeLimitExceeded({ limit: 0, required: 1 })) => Bool.True
			_ => Bool.False
		}
		line_limit = match KernelUnicode.analyze("ଅ🇦", { ..limits(2, 3), max_line_boundaries: runtime_context + 1 }) {
			Err(LineBoundaryLimitExceeded({ limit: 2, required: 3 })) => Bool.True
			_ => Bool.False
		}
		if !grapheme_limit or !line_limit {
			return Err(MissingAtomicLimitRejection)
		}
		plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
		Ok({ bytes, work: [2] })
	}
}

limits : U64, U64 -> KernelUnicode.UnicodeLimits
limits = |scalars, boundaries| {
	{ max_graphemes: scalars, max_line_boundaries: boundaries, max_scalars: scalars, max_script_runs: scalars }
}

lines_equal : List(KernelUnicode.LineBoundary), List({ byte_offset : U64, scalar_offset : U64, decision : [Allowed, Mandatory, Prohibited] }) -> Bool
lines_equal = |actual, expected| {
	actual.map(|boundary| { byte_offset: boundary.byte_offset, scalar_offset: boundary.scalar_offset, decision: boundary.decision }) == expected
}

line_decision_code : List(KernelUnicode.LineBoundary), U64 -> U64
line_decision_code = |boundaries, index| {
	match boundaries.get(index) {
		Err(OutOfBounds) => 9
		Ok(boundary) => match boundary.decision {
			Prohibited => 0
			Allowed => 1
			Mandatory => 2
		}
	}
}

expect {
	result = Fixture.uax_boundary_vectors(0)?
	result.work == [4, 26, 10, 7, 14, 4, 1, 1, 3, 4, 0, 1, 2, 0, 0, 1, 2]
}

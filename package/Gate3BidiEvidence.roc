import KernelBidiBoundary
import KernelEmit
import KernelLineLayout
import KernelStructure
import KernelUnicode
import Layout
import Semantics
import Text

Gate3BidiEvidence :: [].{
	single_level_boundary : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	single_level_boundary = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		limits = KernelBidiBoundary.Limits.make({ max_clusters: 3, max_scalars: 3, max_visual_order: 3 })
		ltr_source = "abc"
		rtl_source = "אבג"
		ltr_analysis = unicode_analysis(ltr_source, 3)?
		rtl_analysis = unicode_analysis(rtl_source, 3)?
		ltr_paragraph = KernelBidiBoundary.analyze_paragraph(ltr_source, ltr_analysis, limits) ? |_| EvidenceFailure
		rtl_paragraph = KernelBidiBoundary.analyze_paragraph(rtl_source, rtl_analysis, limits) ? |_| EvidenceFailure
		ltr_line = line(3, 3)
		rtl_line = line(3, 6)
		ltr_order = KernelBidiBoundary.resolve_single_level_line(ltr_paragraph, ltr_line, clusters(3, 1), limits) ? |_| EvidenceFailure
		rtl_order = KernelBidiBoundary.resolve_single_level_line(rtl_paragraph, rtl_line, clusters(3, 2), limits) ? |_| EvidenceFailure
		paragraph_mismatch = match KernelBidiBoundary.validate_paragraph(ltr_source, ltr_analysis, { ..ltr_paragraph, base_level: Odd }, limits) {
			Err(ParagraphFactsMismatch) => Bool.True
			_ => Bool.False
		}
		malformed_line = { ..rtl_line, source: { ..rtl_line.source, utf8_bytes: Semantics.Range.from_start_and_length(0, 2) } }
		line_mismatch = match KernelBidiBoundary.resolve_single_level_line(rtl_paragraph, malformed_line, clusters(3, 2), limits) {
			Err(InvalidCluster({ cluster: 1 })) => Bool.True
			_ => Bool.False
		}
		if ltr_paragraph.base_level != Even or rtl_paragraph.base_level != Odd or ltr_order.logical_clusters.start() != 0 or ltr_order.logical_clusters.length() != 3 or ltr_order.visual_clusters != [0, 1, 2] or rtl_order.logical_clusters.start() != 0 or rtl_order.logical_clusters.length() != 3 or rtl_order.visual_clusters != [2, 1, 0] or !paragraph_mismatch or !line_mismatch {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({
			bytes,
			work: [
				ltr_paragraph.work.scalar_visits + rtl_paragraph.work.scalar_visits,
				ltr_paragraph.work.strong_class_visits + rtl_paragraph.work.strong_class_visits,
				ltr_order.work.scalar_visits + rtl_order.work.scalar_visits,
				ltr_order.work.cluster_visits + rtl_order.work.cluster_visits,
				ltr_order.work.visual_writes + rtl_order.work.visual_writes,
				if paragraph_mismatch and line_mismatch 2 else 0,
				bytes.len(),
			],
		})
	}
}

unicode_analysis : Str, U64 -> Try(KernelUnicode.UnicodeAnalysis, [EvidenceFailure, InvalidRuntimeGuard])
unicode_analysis = |source, scalars| {
	match KernelUnicode.analyze(
		source,
		{
			max_graphemes: scalars,
			max_line_boundaries: scalars + 1,
			max_scalars: scalars,
			max_script_runs: scalars,
		},
	) {
		Err(_) => Err(EvidenceFailure)
		Ok(analysis) => Ok(analysis)
	}
}

line : U64, U64 -> KernelLineLayout.Line
line = |scalar_length, byte_length| {
	{
		advance: Layout.Unit.from_raw(0),
		clusters: Semantics.Range.from_start_and_length(0, scalar_length),
		source: {
			scalars: Semantics.Range.from_start_and_length(0, scalar_length),
			utf8_bytes: Semantics.Range.from_start_and_length(0, byte_length),
		},
	}
}

clusters : U64, U64 -> List(Text.Cluster)
clusters = |count, byte_width| {
	var $items = []
	var $index = 0
	while $index < count {
		$items = $items.append({
			glyphs: Semantics.Range.from_start_and_length($index, 1),
			kind: OneToOne,
			source: {
				scalars: Semantics.Range.from_start_and_length($index, 1),
				utf8_bytes: Semantics.Range.from_start_and_length($index * byte_width, byte_width),
			},
		})
		$index = $index + 1
	}
	$items
}

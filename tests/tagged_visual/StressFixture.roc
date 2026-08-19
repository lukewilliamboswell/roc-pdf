import pdf.KernelEmit
import Stress
import pdf.KernelStructure

StressFixture :: [].{
	command_stress : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure])
	command_stress = |command_count| command_stress_phase(command_count, 0)

	command_stress_phase : U64, U8 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure])
	command_stress_phase = |command_count, phase| {
		report = Stress.run_phase(command_count, phase) ? |_| EvidenceFailure
		structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
		Ok({
			bytes,
			work: [
				report.commands,
				report.scene_command_visits,
				report.scene_image_placements,
				report.scene_max_graphics_depth,
				report.content_command_visits,
				report.content_image_placements,
				report.content_max_frame_depth,
				report.resource_command_visits,
				report.image_reuses,
				report.image_resource_count,
				report.image_use_count,
				report.image_payload_bytes,
				report.content_bytes,
				bytes.len(),
			],
		})
	}
}

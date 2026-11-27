import pf.File
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import pdf.Image
import pdf.Pdf
import weaver.Cli
import weaver.Opt

Bench :: [].{
	common_args = |default_units| {
		units: Opt.u64({ short: "n", long: "units", help: "Workload size.", default: Value(default_units) }),
		iterations: Opt.u64({ short: "i", long: "iterations", help: "Number of documents to process.", default: Value(1) }),
		compression: Opt.str({ short: "c", long: "compression", help: "Choose balanced, smallest, or fastest.", default: Value("balanced") }),
		delivery: Opt.str({ short: "", long: "delivery", help: "Choose buffered, share, or own.", default: Value("buffered") }),
		max_pages: Opt.u64({ short: "", long: "max-pages", help: "Page budget passed to Pdf.Options.", default: Value(Pdf.Options.default.max_pages) }),
		max_source_script_runs: Opt.maybe_u64({ short: "", long: "max-source-script-runs", help: "Override the scaled script-run budget per body source." }),
		flow_reference_state_units: Opt.maybe_u64({ short: "", long: "flow-reference-state-units", help: "Override the scaled flow-reference state budget per pass." }),
		budget_scale: Opt.u64({ short: "", long: "budget-scale", help: "Multiply the default document capacity budgets for a stress run.", default: Value(1) }),
		image_comparison_bytes: Opt.u64({ short: "", long: "image-comparison-bytes", help: "Byte budget per recent-image comparison lane.", default: Value(Image.Budgets.default.max_identity_comparison_bytes) }),
		prepare_only: Opt.flag({ short: "", long: "prepare-only", help: "Stop after preparing each document." }),
		output: Opt.maybe_str({ short: "", long: "output", help: "Write one generated PDF to this path." }),
	}.Cli

	run! = |args, { name, description, default_units }, build_document| {
		builder = Cli.map(Bench.common_args(default_units), |common| { common, workload: {} })
		Bench.run_with!(args, { name, description }, builder, |units, iteration, _| build_document(units, iteration))
	}

	run_with! = |args, program, builder, build_document|
		Bench.run_configured!(args, program, builder, { defaults: Pdf.Options.default, max_units: U64.highest }, build_document)

	run_configured! = |args, { name, description }, builder, { defaults, max_units }, build_document| {
		parser = Cli.assert_valid(
			Cli.finish(
				builder,
				{ name, version: "unversioned", authors: [], description, text_style: Plain },
			),
		)
		{ common: config, workload } = match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
			Ok(parsed) => parsed
			Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
			Err(InvalidUsage(message)) => return usage!(message)
		}
		if config.units == 0 or config.iterations == 0 {
			return usage!("Workload size and iteration count must both be positive.")
		}
		if config.units > max_units {
			return usage!("Workload size must be at most ${max_units.to_str()}.")
		}
		if config.prepare_only or config.iterations != 1 {
			match config.output {
				Ok(_) => return usage!("Writing an output file requires one full generation.")
				Err(NoValue) => {}
			}
		}
		budget = defaults.budgets
		artifact_budget = defaults.artifact_text_budgets
		source_budget = defaults.source_budgets
		scale = config.budget_scale
		max_scale = U32.highest.to_u64() // (5 * budget.max_content_items)
		if scale == 0 or scale > max_scale {
			return usage!("Budget scale must be between 1 and ${max_scale.to_str()}.")
		}
		options : Pdf.Options
		options = {
			..defaults,
			artifact_text_budgets: {
				max_attached_source_units: artifact_budget.max_attached_source_units * scale,
				max_attached_sources: artifact_budget.max_attached_sources * scale,
				max_drawing_labels: artifact_budget.max_drawing_labels * scale,
				max_furniture_items: artifact_budget.max_furniture_items * scale,
				max_furniture_pieces: artifact_budget.max_furniture_pieces * scale,
				max_page_label_bytes: artifact_budget.max_page_label_bytes * scale,
				max_source_hash_probes: artifact_budget.max_source_hash_probes * scale,
				max_source_inputs: artifact_budget.max_source_inputs * scale,
				max_source_script_runs: artifact_budget.max_source_script_runs * scale,
				max_source_table_slots: artifact_budget.max_source_table_slots * scale,
				max_text_units: artifact_budget.max_text_units * scale,
			},
			image_budgets: { ..defaults.image_budgets, max_identity_comparison_bytes: config.image_comparison_bytes },
			budgets: {
				max_annotations: budget.max_annotations * scale,
				max_content_bytes: budget.max_content_bytes * scale,
				max_content_items: budget.max_content_items * scale,
				max_contents_entries: budget.max_contents_entries * scale,
				max_contents_requests: budget.max_contents_requests * scale,
				max_contents_scan_blocks: budget.max_contents_scan_blocks * scale,
				max_contents_title_overrides: budget.max_contents_title_overrides * scale,
				max_destination_name_bytes: budget.max_destination_name_bytes * scale,
				max_destinations: budget.max_destinations * scale,
				max_flow_reference_layout_work: budget.max_flow_reference_layout_work * scale,
				max_flow_reference_state_units: match config.flow_reference_state_units {
					Ok(limit) => limit
					Err(NoValue) => budget.max_flow_reference_state_units * scale
				},
				max_font_glyphs: budget.max_font_glyphs * scale,
				max_font_mapping_scalars: budget.max_font_mapping_scalars * scale,
				max_font_mappings: budget.max_font_mappings * scale,
				max_font_to_unicode_bytes: budget.max_font_to_unicode_bytes * scale,
				max_index_entries: budget.max_index_entries * scale,
				max_index_locations: budget.max_index_locations * scale,
				max_index_targets_per_term: budget.max_index_targets_per_term * scale,
				max_index_term_bytes: budget.max_index_term_bytes * scale,
				max_link_quads: budget.max_link_quads * scale,
				max_objects: budget.max_objects * scale,
				max_outline_depth: budget.max_outline_depth * scale,
				max_outline_entries: budget.max_outline_entries * scale,
				max_outline_title_bytes: budget.max_outline_title_bytes * scale,
				max_page_label_prefix_bytes: budget.max_page_label_prefix_bytes * scale,
				max_page_label_ranges: budget.max_page_label_ranges * scale,
				max_paint_items: budget.max_paint_items * scale,
				max_payload_bytes: budget.max_payload_bytes * scale,
				max_reference_page_label_bytes: budget.max_reference_page_label_bytes * scale,
				max_source_script_runs: match config.max_source_script_runs {
					Ok(limit) => limit
					Err(NoValue) => budget.max_source_script_runs * scale
				},
				max_table_grid_work: budget.max_table_grid_work * scale,
				max_text_units: budget.max_text_units * scale,
				max_uri_bytes: budget.max_uri_bytes * scale,
			},
			source_budgets: {
				max_foregrounds: source_budget.max_foregrounds * scale,
				max_input_bytes: source_budget.max_input_bytes * scale,
				max_lines: source_budget.max_lines * scale,
				max_output_bytes: source_budget.max_output_bytes * scale,
			},
			max_pages: config.max_pages,
			compression: match config.compression {
				"balanced" => Balanced
				"smallest" => Smallest
				"fastest" => Fastest
				_ => return usage!("Compression must be balanced, smallest, or fastest.")
			},
		}
		delivery = match config.delivery {
			"buffered" => Buffered
			"share" => Chunked(Pdf.ChunkRetention.ShareUnchangedResources)
			"own" => Chunked(Pdf.ChunkRetention.OwnChunks)
			_ => return usage!("Delivery must be buffered, share, or own.")
		}

		var $iteration = 0
		var $output_bytes = 0
		while $iteration < config.iterations {
			document = build_document(config.units, $iteration, workload)
			prepared = Pdf.prepare(document, options).map_err(|error| PrepareFailed(error))?
			if !config.prepare_only {
				bytes = match delivery {
					Buffered => {
						output = Pdf.to_bytes_prepared(prepared) ? EmitFailed
						match config.output {
							Ok(path) => Path.utf8(path).write_bytes!(output) ? WriteFailed
							Err(NoValue) => {}
						}
						output.len()
					}
					Chunked(retention) => {
						encoder = Pdf.to_chunks_prepared(prepared, retention) ? EmitFailed
						match config.output {
							Ok(path) => File.with_writer!(Path.utf8(path), Truncate, {}, |writer| Bench.drain!(encoder, |chunk| writer.write_bytes!(chunk))) ? WriteFailed
							Err(NoValue) => Bench.drain!(encoder, |_| Ok({})) ? WriteFailed
						}
					}
				}
				$output_bytes = $output_bytes + bytes
			}
			$iteration = $iteration + 1
		}

		phase = if (config.prepare_only) "prepare" else "full"
		Stdout.line!("${name}: phase=${phase} units=${config.units.to_str()} iterations=${config.iterations.to_str()} output_bytes=${$output_bytes.to_str()}").map_err(|error| OutputFailed(error))
	}

	drain! = |encoder, consume!| {
		var $encoder = encoder
		var $bytes = 0
		while True {
			match Pdf.next_chunk($encoder) {
				Done => return Ok($bytes)
				Emit(chunk, next) => {
					$bytes = $bytes + chunk.len()
					consume!(chunk)?
					$encoder = next
				}
			}
		}
	}

	usage! = |message| {
		Stderr.line!(message).map_err(|error| OutputFailed(error))?
		Err(Exit(2))
	}
}

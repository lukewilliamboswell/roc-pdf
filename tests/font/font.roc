app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "text-layout font evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "font" {
		return match Fixture.font_inspection(args.len() - 2) {
			Err(_) => {
				crash "text-layout font inspection evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "plan" {
		return match Fixture.font_planning(args.len() - 2) {
			Err(_) => {
				crash "text-layout font planning evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "caller" {
		return match Fixture.caller_registration(args.len() - 2) {
			Err(_) => {
				crash "text-layout caller font registration evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "multi" {
		return match Fixture.multi_face_planning(args.len() - 2) {
			Err(_) => {
				crash "text-layout multi-face planning evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "probe" {
		count = match args.get(2) {
			Err(OutOfBounds) => {
				crash "text-layout adversarial probe requires a cluster count"
			}
			Ok(value) => match U64.from_str(value) {
				Err(_) => {
					crash "text-layout adversarial probe cluster count is invalid"
				}
				Ok(parsed) => parsed
			}
		}
		return match Fixture.multi_face_probe_scale(count, args.len() - 3) {
			Err(_) => {
				crash "text-layout adversarial probe evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown text-layout font evidence mode"
}

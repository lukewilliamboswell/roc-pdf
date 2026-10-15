# The audited built-in face, generated into `package/RocPdfSans-Regular.ttf`
# by scripts/build_builtin_font.py. The byte import keeps the face inside the
# package directory, so `roc bundle` ships it once scripts/bundle.sh lists it.
import "RocPdfSans-Regular.ttf" as font_bytes : List(U8)

KernelBuiltInFont :: [].{
	bytes : List(U8)
	bytes = font_bytes
}

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "fpdfview.h"

/* Test-only: render every page of the original document at 72 dpi. */
static void fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(1);
}

static void dimensions(FPDF_PAGE page, int *width, int *height) {
    double w = ceil(FPDF_GetPageWidthF(page));
    double h = ceil(FPDF_GetPageHeightF(page));
    if (!isfinite(w) || !isfinite(h) || w < 1 || h < 1 ||
        w > 64000000 || h > 64000000 || w * h > 64000000) {
        fail("PDFium page exceeds render pixel budget");
    }
    *width = (int)w;
    *height = (int)h;
}

int main(int argc, char **argv) {
    if (argc != 3) fail("usage: pdfium_pages INPUT.pdf EXISTING_OUTPUT_DIRECTORY");
    FPDF_InitLibrary();
    FPDF_DOCUMENT document = FPDF_LoadDocument(argv[1], NULL);
    if (!document) fail("PDFium could not load document");
    int count = FPDF_GetPageCount(document);
    if (count < 1 || count > 128) fail("PDFium page count outside 1..128");
    uint64_t pixels = 0;
    for (int index = 0; index < count; index++) {
        FPDF_PAGE page = FPDF_LoadPage(document, index);
        if (!page) fail("PDFium could not load page during budget check");
        int width, height;
        dimensions(page, &width, &height);
        pixels += (uint64_t)width * (uint64_t)height;
        FPDF_ClosePage(page);
        if (pixels > 64000000) fail("PDFium document exceeds render pixel budget");
    }
    for (int index = 0; index < count; index++) {
        FPDF_PAGE page = FPDF_LoadPage(document, index);
        if (!page) fail("PDFium could not load page for rendering");
        int width, height;
        dimensions(page, &width, &height);
        FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 1);
        if (!bitmap || !FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff)) {
            fail("PDFium could not initialize bitmap");
        }
        FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0);
        char path[4096];
        int length = snprintf(path, sizeof(path), "%s/page-%04d.ppm", argv[2], index + 1);
        if (length < 0 || (size_t)length >= sizeof(path)) fail("PDFium output path too long");
        FILE *output = fopen(path, "wb");
        if (!output) fail("PDFium could not open output");
        if (fprintf(output, "P6\n%d %d\n255\n", width, height) < 0) fail("PDFium header write failed");
        const uint8_t *pixels = FPDFBitmap_GetBuffer(bitmap);
        int stride = FPDFBitmap_GetStride(bitmap);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                const uint8_t *pixel = pixels + y * stride + x * 4;
                uint8_t rgb[3] = {pixel[2], pixel[1], pixel[0]};
                if (fwrite(rgb, 1, 3, output) != 3) fail("PDFium pixel write failed");
            }
        }
        if (fclose(output) != 0) fail("PDFium close failed");
        FPDFBitmap_Destroy(bitmap);
        FPDF_ClosePage(page);
    }
    printf("%d\n", count);
    FPDF_CloseDocument(document);
    FPDF_DestroyLibrary();
    return 0;
}

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fpdfview.h"

static void fail(const char *message) {
    fputs(message, stderr);
    fputc('\n', stderr);
    exit(1);
}

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) {
        fail("usage: pdfium_render INPUT.pdf OUTPUT.ppm [1]");
    }
    float scale = 10.0f;
    if (argc == 4) {
        if (strcmp(argv[3], "1") != 0) {
            fail("pdfium_render supports only scale 1 or the default scale 10");
        }
        scale = 1.0f;
    }

    FPDF_InitLibrary();
    FPDF_DOCUMENT document = FPDF_LoadDocument(argv[1], NULL);
    if (document == NULL) {
        fail("PDFium could not load the renderer fixture");
    }
    if (FPDF_GetPageCount(document) != 1) {
        fail("renderer fixture must have one page");
    }

    FPDF_PAGE page = FPDF_LoadPage(document, 0);
    if (page == NULL) {
        fail("PDFium could not load page zero");
    }
    int width = (int)(FPDF_GetPageWidthF(page) * scale + 0.5f);
    int height = (int)(FPDF_GetPageHeightF(page) * scale + 0.5f);
    if (width <= 0 || height <= 0) {
        fail("PDFium returned invalid page dimensions");
    }

    FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 1);
    if (bitmap == NULL) {
        fail("PDFium could not allocate the render bitmap");
    }
    if (!FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff)) {
        fail("PDFium could not initialize the render bitmap");
    }
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0);

    FILE *output = fopen(argv[2], "wb");
    if (output == NULL) {
        fail("could not create PDFium PPM output");
    }
    if (fprintf(output, "P6\n%d %d\n255\n", width, height) < 0) {
        fail("could not write PDFium PPM header");
    }
    const uint8_t *pixels = (const uint8_t *)FPDFBitmap_GetBuffer(bitmap);
    int stride = FPDFBitmap_GetStride(bitmap);
    for (int y = 0; y < height; y++) {
        const uint8_t *row = pixels + y * stride;
        for (int x = 0; x < width; x++) {
            const uint8_t *bgra = row + x * 4;
            if (fputc(bgra[2], output) == EOF || fputc(bgra[1], output) == EOF ||
                fputc(bgra[0], output) == EOF) {
                fail("could not write PDFium PPM pixels");
            }
        }
    }
    if (fclose(output) != 0) {
        fail("could not close PDFium PPM output");
    }

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);
    FPDF_CloseDocument(document);
    FPDF_DestroyLibrary();
    return 0;
}

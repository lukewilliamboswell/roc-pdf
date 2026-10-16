import java.awt.image.BufferedImage;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.pdfbox.text.PDFTextStripper;

/** Bounded rendering and extraction of every page of the original PDF bytes. */
public final class PdfBoxPages {
    private static final int MAX_PAGES = 128;
    private static final long MAX_PIXELS = 64_000_000L;

    private PdfBoxPages() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: PdfBoxPages INPUT.pdf OUTPUT_DIRECTORY");
        }
        Path directory = Path.of(args[1]);
        Files.createDirectories(directory);
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            int pages = document.getNumberOfPages();
            if (pages < 1 || pages > MAX_PAGES) {
                throw new IllegalArgumentException("page count outside 1.." + MAX_PAGES);
            }
            long pixels = 0;
            for (int page = 0; page < pages; page++) {
                var box = document.getPage(page).getCropBox();
                double width = Math.ceil(box.getWidth());
                double height = Math.ceil(box.getHeight());
                if (!Double.isFinite(width) || !Double.isFinite(height) || width < 1 || height < 1
                    || width > MAX_PIXELS || height > MAX_PIXELS || width * height > MAX_PIXELS - pixels) {
                    throw new IllegalArgumentException("render pixel budget exceeded");
                }
                pixels += (long)(width * height);
            }
            PDFRenderer renderer = new PDFRenderer(document);
            renderer.setSubsamplingAllowed(false);
            PDFTextStripper stripper = new PDFTextStripper();
            stripper.setSortByPosition(false);
            stripper.setSuppressDuplicateOverlappingText(false);
            stripper.setLineSeparator("\n");
            stripper.setPageStart("");
            stripper.setPageEnd("");
            for (int page = 0; page < pages; page++) {
                String stem = String.format("page-%04d", page + 1);
                BufferedImage image = renderer.renderImageWithDPI(page, 72.0f, ImageType.RGB);
                writePpm(image, directory.resolve(stem + ".ppm").toFile());
                image.flush();
                stripper.setStartPage(page + 1);
                stripper.setEndPage(page + 1);
                Files.writeString(directory.resolve(stem + ".txt"), stripper.getText(document), StandardCharsets.UTF_8);
            }
            System.out.println(pages);
        }
    }

    private static void writePpm(BufferedImage image, File output) throws IOException {
        try (BufferedOutputStream stream = new BufferedOutputStream(new FileOutputStream(output))) {
            stream.write(("P6\n" + image.getWidth() + " " + image.getHeight() + "\n255\n").getBytes(StandardCharsets.US_ASCII));
            for (int y = 0; y < image.getHeight(); y++) {
                for (int x = 0; x < image.getWidth(); x++) {
                    int rgb = image.getRGB(x, y);
                    stream.write((rgb >>> 16) & 0xff);
                    stream.write((rgb >>> 8) & 0xff);
                    stream.write(rgb & 0xff);
                }
            }
        }
    }
}

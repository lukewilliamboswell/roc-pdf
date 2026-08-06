import java.awt.image.BufferedImage;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;

public final class PdfBoxRender {
    private PdfBoxRender() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: PdfBoxRender INPUT.pdf OUTPUT.ppm");
        }
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            if (document.getNumberOfPages() != 1) {
                throw new IllegalArgumentException("Gate 2 renderer fixture must have one page");
            }
            PDFRenderer renderer = new PDFRenderer(document);
            renderer.setSubsamplingAllowed(false);
            BufferedImage image = renderer.renderImageWithDPI(0, 720.0f, ImageType.RGB);
            writePpm(image, new File(args[1]));
        }
    }

    private static void writePpm(BufferedImage image, File output) throws IOException {
        try (BufferedOutputStream stream = new BufferedOutputStream(new FileOutputStream(output))) {
            String header = "P6\n" + image.getWidth() + " " + image.getHeight() + "\n255\n";
            stream.write(header.getBytes(StandardCharsets.US_ASCII));
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

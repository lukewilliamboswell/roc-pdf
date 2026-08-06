import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;

public final class PdfBoxTextExtract {
    private PdfBoxTextExtract() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: PdfBoxTextExtract INPUT.pdf");
        }
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            if (document.getNumberOfPages() != 1) {
                throw new IllegalArgumentException("text extraction fixture must have one page");
            }
            String text = new PDFTextStripper().getText(document);
            System.out.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }
}

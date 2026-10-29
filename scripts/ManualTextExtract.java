import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.contentstream.operator.Operator;
import org.apache.pdfbox.pdfparser.PDFStreamParser;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.pdfbox.text.PDFTextStripper;

/** Independent original-byte extraction for the multipage published manual. */
public final class ManualTextExtract {
    private ManualTextExtract() {}
    public static void main(String[] args) throws Exception {
        if (args.length != 1 && args.length != 2) throw new IllegalArgumentException("usage: ManualTextExtract INPUT.pdf [REVIEW_DIRECTORY]");
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            if (document.getNumberOfPages() < 2 || document.getNumberOfPages() > 512)
                throw new IllegalArgumentException("manual page count outside 2..512");
            PDFTextStripper stripper = new PDFTextStripper();
            stripper.setSortByPosition(false);
            stripper.setPageEnd("\f");
            System.out.write(stripper.getText(document).getBytes(StandardCharsets.UTF_8));
            if (args.length == 2) {
                Path output = Path.of(args[1]);
                Files.createDirectories(output);
                PDFRenderer renderer = new PDFRenderer(document);
                int figures = 0;
                int tables = 0;
                for (int page = 0; page < document.getNumberOfPages(); page++) {
                    boolean image = false;
                    var resources = document.getPage(page).getResources();
                    var tokens = new PDFStreamParser(document.getPage(page)).parse();
                    for (int token = 1; token < tokens.size(); token++) {
                        if (tokens.get(token) instanceof Operator operation && operation.getName().equals("Do")
                            && tokens.get(token - 1) instanceof COSName name
                            && resources.getXObject(name) instanceof PDImageXObject) image = true;
                    }
                    boolean table = false;
                    if (tables < 2) {
                        stripper.setStartPage(page + 1);
                        stripper.setEndPage(page + 1);
                        table = stripper.getText(document).contains("Authoring surface");
                    }
                    if (page == 0 || (image && figures < 3) || table) {
                        var box = document.getPage(page).getCropBox();
                        if (box.getWidth() * box.getHeight() > 1_000_000)
                            throw new IllegalArgumentException("manual preview pixel budget exceeded");
                        ImageIO.write(renderer.renderImageWithDPI(page, 72), "png",
                            output.resolve(String.format("pdf-page-%03d.png", page + 1)).toFile());
                        if (image) figures++;
                        if (table) tables++;
                    }
                }
                if (figures != 3) throw new IllegalArgumentException("manual needs three independently rendered figure pages");
            }
        }
    }
}

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentCatalog;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.common.PDPageLabels;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.interactive.action.PDAction;
import org.apache.pdfbox.pdmodel.interactive.action.PDActionGoTo;
import org.apache.pdfbox.pdmodel.interactive.action.PDActionURI;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotation;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotationLink;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDNamedDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageXYZDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem;

/**
 * Emits a deterministic navigation report: every link annotation with its
 * resolved geometric target, the expanded page-label sequence, and the
 * outline hierarchy with each entry's destination resolved through the
 * document's named-destination name tree. PDFBox navigates through the
 * explicit /D geometric destinations; it never reads /SD, which is exactly
 * the independent geometric-fallback evidence this report provides.
 */
public final class PdfBoxNavigate {
    private PdfBoxNavigate() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: PdfBoxNavigate INPUT.pdf");
        }
        StringBuilder report = new StringBuilder();
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            PDDocumentCatalog catalog = document.getDocumentCatalog();
            int pageCount = document.getNumberOfPages();
            for (int index = 0; index < pageCount; index += 1) {
                PDPage page = document.getPage(index);
                List<PDAnnotation> annotations = page.getAnnotations();
                for (PDAnnotation annotation : annotations) {
                    if (!(annotation instanceof PDAnnotationLink)) {
                        throw new IllegalArgumentException("unsupported annotation type " + annotation.getSubtype());
                    }
                    PDAnnotationLink link = (PDAnnotationLink) annotation;
                    PDRectangle rectangle = link.getRectangle();
                    float[] quads = link.getQuadPoints();
                    int quadCount = quads == null ? 0 : quads.length / 8;
                    String target;
                    PDAction action = link.getAction();
                    if (action instanceof PDActionURI) {
                        target = "uri=" + ((PDActionURI) action).getURI();
                    } else if (action instanceof PDActionGoTo) {
                        PDDestination destination = ((PDActionGoTo) action).getDestination();
                        if (!(destination instanceof PDPageXYZDestination)) {
                            throw new IllegalArgumentException("GoTo destination is not /XYZ");
                        }
                        PDPageXYZDestination xyz = (PDPageXYZDestination) destination;
                        int destinationPage = pageIndex(document, xyz);
                        target = String.format(Locale.ROOT, "goto=%d left=%d top=%d", destinationPage, xyz.getLeft(), xyz.getTop());
                    } else {
                        throw new IllegalArgumentException("unsupported action");
                    }
                    report.append(String.format(
                        Locale.ROOT,
                        "annot page=%d rect=%.0f,%.0f,%.0f,%.0f quads=%d %s%n",
                        index,
                        rectangle.getLowerLeftX(),
                        rectangle.getLowerLeftY(),
                        rectangle.getUpperRightX(),
                        rectangle.getUpperRightY(),
                        quadCount,
                        target));
                }
            }
            PDPageLabels labels = catalog.getPageLabels();
            if (labels != null) {
                String[] byPage = labels.getLabelsByPageIndices();
                for (int index = 0; index < byPage.length; index += 1) {
                    report.append(String.format(Locale.ROOT, "label page=%d text=%s%n", index, byPage[index]));
                }
            }
            PDDocumentOutline outline = catalog.getDocumentOutline();
            if (outline != null) {
                appendOutline(document, outline.getFirstChild(), 0, report);
            }
        }
        System.out.write(report.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static void appendOutline(PDDocument document, PDOutlineItem item, int depth, StringBuilder report) throws IOException {
        while (item != null) {
            PDDestination destination = item.getDestination();
            if (!(destination instanceof PDNamedDestination)) {
                throw new IllegalArgumentException("outline destination is not a name");
            }
            PDPageDestination resolved =
                document.getDocumentCatalog().findNamedDestinationPage((PDNamedDestination) destination);
            if (resolved == null) {
                throw new IllegalArgumentException("outline destination name did not resolve");
            }
            int page = resolved.retrievePageNumber();
            report.append(String.format(Locale.ROOT, "outline depth=%d page=%d title=%s%n", depth, page, item.getTitle()));
            appendOutline(document, item.getFirstChild(), depth + 1, report);
            item = item.getNextSibling();
        }
    }

    private static int pageIndex(PDDocument document, PDPageXYZDestination destination) {
        PDPage target = destination.getPage();
        int pageCount = document.getNumberOfPages();
        for (int index = 0; index < pageCount; index += 1) {
            if (document.getPage(index).getCOSObject() == target.getCOSObject()) {
                return index;
            }
        }
        throw new IllegalArgumentException("destination page is not in the document");
    }
}

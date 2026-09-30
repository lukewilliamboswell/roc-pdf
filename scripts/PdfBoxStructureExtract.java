import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.COSBase;
import org.apache.pdfbox.cos.COSDictionary;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.cos.COSString;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.documentinterchange.logicalstructure.PDMarkedContentReference;
import org.apache.pdfbox.pdmodel.documentinterchange.logicalstructure.PDObjectReference;
import org.apache.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureElement;
import org.apache.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureTreeRoot;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotation;

/**
 * Prints a PDF's structure tree as one normalized line, using only PDFBox's
 * logical-structure API: each element as its role and its /Lang, /Alt, /E,
 * /ActualText, and /ID facts, followed by its kids in /K order (child
 * elements, "mcid pN:M" content items, "objr Subtype pN" object
 * references, and "Artifact" for contextual Artifact elements). Page numbers
 * are zero-based page-tree positions. It is an extraction path independent
 * of the project's own byte-level parser; scripts/check_structure_extraction.py
 * compares the two.
 */
public final class PdfBoxStructureExtract {
    private PdfBoxStructureExtract() {}

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: PdfBoxStructureExtract INPUT.pdf");
        }
        try (PDDocument document = Loader.loadPDF(new File(args[0]))) {
            PDStructureTreeRoot root = document.getDocumentCatalog().getStructureTreeRoot();
            if (root == null) {
                throw new IllegalArgumentException("document has no structure tree");
            }
            List<Object> kids = root.getKids();
            if (kids.size() != 1 || !(kids.get(0) instanceof PDStructureElement)) {
                throw new IllegalArgumentException("structure tree root does not hold one element");
            }
            String language = document.getDocumentCatalog().getLanguage();
            String line = element(document, (PDStructureElement) kids.get(0), language, null) + "\n";
            System.out.write(line.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static String element(PDDocument document, PDStructureElement element, String inherited, PDPage inheritedPage) {
        List<String> facts = new ArrayList<>();
        facts.add(element.getStructureType());
        String language = inherited;
        if (element.getLanguage() != null) {
            facts.add("Lang=" + element.getLanguage());
            language = element.getLanguage();
        }
        if (element.getAlternateDescription() != null) {
            facts.add("Alt=" + quoted(element.getAlternateDescription()));
        }
        if (element.getExpandedForm() != null) {
            facts.add("E=" + quoted(element.getExpandedForm()));
        }
        if (element.getActualText() != null) {
            facts.add("ActualText=" + quoted(element.getActualText()));
        }
        COSBase identifier = element.getCOSObject().getDictionaryObject(COSName.ID);
        if (identifier instanceof COSString) {
            facts.add("ID=" + ((COSString) identifier).getString());
        }
        PDPage page = element.getPage() != null ? element.getPage() : inheritedPage;
        List<String> leaves = new ArrayList<>();
        for (Object kid : element.getKids()) {
            if (kid instanceof PDStructureElement) {
                PDStructureElement child = (PDStructureElement) kid;
                leaves.add("Artifact".equals(child.getStructureType()) ? "Artifact" : element(document, child, language, page));
            } else if (kid instanceof PDMarkedContentReference) {
                PDMarkedContentReference reference = (PDMarkedContentReference) kid;
                PDPage owner = reference.getPage() != null ? reference.getPage() : page;
                leaves.add("mcid p" + document.getPages().indexOf(owner) + ":" + reference.getMCID());
            } else if (kid instanceof Integer) {
                leaves.add("mcid p" + document.getPages().indexOf(page) + ":" + kid);
            } else if (kid instanceof PDObjectReference) {
                PDObjectReference reference = (PDObjectReference) kid;
                COSDictionary dictionary = reference.getCOSObject();
                COSBase pageValue = dictionary.getDictionaryObject(COSName.PG);
                PDPage owner = pageValue instanceof COSDictionary ? new PDPage((COSDictionary) pageValue) : page;
                Object referenced = reference.getReferencedObject();
                if (!(referenced instanceof PDAnnotation)) {
                    throw new IllegalArgumentException("an OBJR does not reference an annotation");
                }
                leaves.add("objr " + ((PDAnnotation) referenced).getSubtype() + " p" + document.getPages().indexOf(owner));
            } else {
                throw new IllegalArgumentException("unsupported structure kid " + kid);
            }
        }
        String label = String.join(" ", facts);
        return leaves.isEmpty() ? label : label + " [" + String.join(", ", leaves) + "]";
    }

    /** Python's repr() quoting, so lines compare with the byte-level checker. */
    private static String quoted(String value) {
        String escaped = value.replace("\\", "\\\\");
        if (value.contains("'") && !value.contains("\"")) {
            return "\"" + escaped + "\"";
        }
        return "'" + escaped.replace("'", "\\'") + "'";
    }
}

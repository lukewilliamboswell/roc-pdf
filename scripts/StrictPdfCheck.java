import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogManager;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

import org.apache.pdfbox.contentstream.operator.Operator;
import org.apache.pdfbox.cos.COSArray;
import org.apache.pdfbox.cos.COSBase;
import org.apache.pdfbox.cos.COSDictionary;
import org.apache.pdfbox.cos.COSDocument;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.cos.COSObject;
import org.apache.pdfbox.cos.COSObjectKey;
import org.apache.pdfbox.cos.COSStream;
import org.apache.pdfbox.cos.COSString;
import org.apache.pdfbox.io.RandomAccessReadBufferedFile;
import org.apache.pdfbox.pdfparser.PDFParser;
import org.apache.pdfbox.pdfparser.PDFStreamParser;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageTree;
import org.apache.pdfbox.pdmodel.common.PDRectangle;

public final class StrictPdfCheck
{
    private static final String PDFBOX_VERSION = "3.0.8";

    private StrictPdfCheck()
    {
    }

    private static final class ValidationFailure extends Exception
    {
        private static final long serialVersionUID = 1L;

        ValidationFailure(String message)
        {
            super(message);
        }

        ValidationFailure(String message, Throwable cause)
        {
            super(message, cause);
        }
    }

    private static final class StrictParseFailure extends Exception
    {
        private static final long serialVersionUID = 1L;

        StrictParseFailure(IOException cause)
        {
            super(cause.getMessage(), cause);
        }
    }

    private static final class WarningHandler extends Handler
    {
        private final List<String> warnings = new ArrayList<>();

        @Override
        public void publish(LogRecord record)
        {
            if (record != null && record.getLevel().intValue() >= Level.WARNING.intValue())
            {
                warnings.add(record.getLoggerName() + ": " + record.getMessage());
            }
        }

        @Override
        public void flush()
        {
        }

        @Override
        public void close()
        {
        }
    }

    private static final class Facts
    {
        long contentBytes;
        long operators;
    }

    private static void require(boolean condition, String message) throws ValidationFailure
    {
        if (!condition)
        {
            throw new ValidationFailure(message);
        }
    }

    private static int parseExpected(String value, String label) throws ValidationFailure
    {
        try
        {
            int parsed = Integer.parseInt(value);
            require(parsed >= 0, label + " must be non-negative");
            return parsed;
        }
        catch (NumberFormatException exception)
        {
            throw new ValidationFailure(label + " must be an integer", exception);
        }
    }

    private static long parseExpectedLong(String value, String label) throws ValidationFailure
    {
        try
        {
            long parsed = Long.parseLong(value);
            require(parsed >= 0, label + " must be non-negative");
            return parsed;
        }
        catch (NumberFormatException exception)
        {
            throw new ValidationFailure(label + " must be an integer", exception);
        }
    }

    private static String implementationVersion() throws ValidationFailure
    {
        String version = PDFParser.class.getPackage().getImplementationVersion();
        require(PDFBOX_VERSION.equals(version),
                "expected PDFBox " + PDFBOX_VERSION + ", got " + String.valueOf(version));
        return version;
    }

    private static COSDictionary dictionary(COSBase value, String label) throws ValidationFailure
    {
        require(value instanceof COSDictionary, label + " must be a dictionary");
        return (COSDictionary) value;
    }

    private static void validateIdentifier(COSDictionary trailer) throws ValidationFailure
    {
        COSArray identifier = trailer.getCOSArray(COSName.ID);
        require(identifier != null && identifier.size() == 2, "xref /ID must contain two values");
        COSBase first = identifier.getObject(0);
        COSBase second = identifier.getObject(1);
        require(first instanceof COSString && second instanceof COSString,
                "xref /ID values must be strings");
        byte[] firstBytes = ((COSString) first).getBytes();
        byte[] secondBytes = ((COSString) second).getBytes();
        require(firstBytes.length == 32, "xref /ID must use a 32-byte SHA-256 value");
        require(java.util.Arrays.equals(firstBytes, secondBytes),
                "initial xref /ID values must be identical");
    }

    private static int validateObjects(COSDocument cosDocument, int expectedObjects,
            int expectedPages, int expectedPageTreeNodes) throws IOException, ValidationFailure
    {
        Map<COSObjectKey, Long> xref = cosDocument.getXrefTable();
        require(xref.size() == expectedObjects,
                "expected " + expectedObjects + " xref objects, got " + xref.size());
        require(cosDocument.getHighestXRefObjectNumber() == expectedObjects,
                "highest xref object number does not match the contiguous object count");
        Set<Long> numbers = new HashSet<>();
        int catalogs = 0;
        int pageTreeNodes = 0;
        int pages = 0;
        int xrefStreams = 0;
        for (Map.Entry<COSObjectKey, Long> entry : xref.entrySet())
        {
            COSObjectKey key = entry.getKey();
            require(key.getGeneration() == 0, "object " + key.getNumber() + " has nonzero generation");
            require(key.getNumber() > 0 && key.getNumber() <= expectedObjects,
                    "object number is outside the expected contiguous range: " + key.getNumber());
            require(numbers.add(key.getNumber()), "duplicate object number " + key.getNumber());
            require(entry.getValue() >= 0, "object " + key.getNumber() + " has a negative xref offset");
            COSBase value = cosDocument.getObjectFromPool(key).getObject();
            require(value != null, "object " + key.getNumber() + " did not dereference");
            if (value instanceof COSDictionary)
            {
                COSName type = ((COSDictionary) value).getCOSName(COSName.TYPE);
                if (COSName.CATALOG.equals(type))
                {
                    catalogs++;
                }
                else if (COSName.PAGES.equals(type))
                {
                    pageTreeNodes++;
                }
                else if (COSName.PAGE.equals(type))
                {
                    pages++;
                }
                else if (COSName.XREF.equals(type))
                {
                    xrefStreams++;
                }
            }
        }
        require(numbers.size() == expectedObjects, "xref object numbers are not unique");
        for (long number = 1; number <= expectedObjects; number++)
        {
            require(numbers.contains(number), "xref is missing object " + number);
        }
        require(catalogs == 1, "expected one catalog object, got " + catalogs);
        require(pageTreeNodes == expectedPageTreeNodes,
                "expected " + expectedPageTreeNodes + " page-tree nodes, got " + pageTreeNodes);
        require(pages == expectedPages, "expected " + expectedPages + " page objects, got " + pages);
        require(xrefStreams == 1, "expected one xref stream object, got " + xrefStreams);
        return pageTreeNodes;
    }

    private static long validateDecodedContent(PDPage page, boolean generatedPattern)
            throws IOException, ValidationFailure
    {
        long length = 0;
        try (InputStream input = page.getContents())
        {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1)
            {
                for (int index = 0; index < read; index++)
                {
                    byte value = buffer[index];
                    if (generatedPattern)
                    {
                        byte expected;
                        switch ((int) (length % 4))
                        {
                            case 0:
                                expected = 'q';
                                break;
                            case 1:
                            case 3:
                                expected = ' ';
                                if (length % 4 == 3)
                                {
                                    expected = '\n';
                                }
                                break;
                            case 2:
                                expected = 'Q';
                                break;
                            default:
                                throw new AssertionError();
                        }
                        require(value == expected,
                                "generated content differs at decoded byte " + length);
                    }
                    else
                    {
                        require(value == ' ' || value == '\t' || value == '\r' || value == '\n',
                                "non-generated content must be empty or whitespace-only");
                    }
                    length++;
                }
            }
        }
        return length;
    }

    private static long validateOperators(PDPage page) throws IOException, ValidationFailure
    {
        PDFStreamParser parser = new PDFStreamParser(page);
        long count = 0;
        int graphicsDepth = 0;
        try
        {
            Object token;
            while ((token = parser.parseNextToken()) != null)
            {
                require(token instanceof Operator, "content stream contains an unexpected operand");
                String name = ((Operator) token).getName();
                if ("q".equals(name))
                {
                    require(graphicsDepth == 0, "generated q/Q pattern is not alternating");
                    graphicsDepth = 1;
                }
                else if ("Q".equals(name))
                {
                    require(graphicsDepth == 1, "content stream restores an unsaved graphics state");
                    graphicsDepth = 0;
                }
                else
                {
                    throw new ValidationFailure("unexpected content operator " + name);
                }
                count++;
            }
        }
        finally
        {
            parser.close();
        }
        require(graphicsDepth == 0, "content stream leaves the graphics state unbalanced");
        return count;
    }

    private static Facts validatePages(PDDocument document, int expectedPages,
            long expectedContentBytes, long expectedOperators) throws IOException, ValidationFailure
    {
        require(document.getNumberOfPages() == expectedPages,
                "expected " + expectedPages + " pages, got " + document.getNumberOfPages());
        PDPageTree pageTree = document.getPages();
        require(pageTree.getCount() == expectedPages, "page-tree /Count does not match page iteration");
        Facts facts = new Facts();
        int pageCount = 0;
        for (PDPage page : pageTree)
        {
            COSDictionary pageDictionary = page.getCOSObject();
            require(COSName.PAGE.equals(pageDictionary.getCOSName(COSName.TYPE)),
                    "page dictionary has the wrong /Type");
            COSBase parent = pageDictionary.getItem(COSName.PARENT);
            require(parent instanceof COSObject && ((COSObject) parent).getKey() != null
                            && ((COSObject) parent).getKey().getGeneration() == 0,
                    "page /Parent must be an indirect generation-zero reference");
            COSBase contents = pageDictionary.getItem(COSName.CONTENTS);
            require(contents instanceof COSObject && ((COSObject) contents).getKey() != null
                            && ((COSObject) contents).getKey().getGeneration() == 0,
                    "page /Contents must be an indirect generation-zero reference");
            COSDictionary stream = dictionary(((COSObject) contents).getObject(), "page /Contents");
            require(stream instanceof COSStream, "page /Contents must resolve to a stream");
            COSBase length = stream.getItem(COSName.LENGTH);
            require(length instanceof COSObject && ((COSObject) length).getKey() != null
                            && ((COSObject) length).getKey().getGeneration() == 0,
                    "content /Length must be an indirect generation-zero reference");
            require(page.getResources() != null && page.getResources().getCOSObject().size() == 0,
                    "structural-kernel structural page resources must be present and empty");
            PDRectangle mediaBox = page.getMediaBox();
            require(mediaBox.getLowerLeftX() == 0 && mediaBox.getLowerLeftY() == 0
                            && mediaBox.getWidth() == 595 && mediaBox.getHeight() == 842,
                    "page media box is not the expected A4 rectangle");
            facts.contentBytes += validateDecodedContent(page, expectedOperators > 0);
            facts.operators += validateOperators(page);
            pageCount++;
        }
        require(pageCount == expectedPages, "page iterator count differs from the expected page count");
        require(facts.contentBytes == expectedContentBytes,
                "expected " + expectedContentBytes + " decoded content bytes, got " + facts.contentBytes);
        require(facts.operators == expectedOperators,
                "expected " + expectedOperators + " content operators, got " + facts.operators);
        return facts;
    }

    private static void validateDocument(Path path, int expectedPages, int expectedObjects,
            int expectedPageTreeNodes, long expectedContentBytes, long expectedOperators)
            throws StrictParseFailure, ValidationFailure
    {
        System.setProperty("org.apache.commons.logging.Log",
                "org.apache.commons.logging.impl.Jdk14Logger");
        Logger rootLogger = LogManager.getLogManager().getLogger("");
        for (Handler handler : rootLogger.getHandlers())
        {
            rootLogger.removeHandler(handler);
        }
        WarningHandler warningHandler = new WarningHandler();
        warningHandler.setLevel(Level.ALL);
        rootLogger.addHandler(warningHandler);
        rootLogger.setLevel(Level.ALL);

        PrintStream originalError = System.err;
        ByteArrayOutputStream diagnosticBytes = new ByteArrayOutputStream();
        PDDocument document = null;
        RandomAccessReadBufferedFile source = null;
        Facts facts;
        int pageTreeNodes;
        try
        {
            System.setErr(new PrintStream(diagnosticBytes, true, "UTF-8"));
            try
            {
                source = new RandomAccessReadBufferedFile(path);
                PDFParser parser = new PDFParser(source);
                try
                {
                    document = parser.parse(false);
                }
                catch (IOException exception)
                {
                    throw new StrictParseFailure(exception);
                }
                require(document.getVersion() == 2.0f, "PDF version is not 2.0");
                require(!document.isEncrypted(), "structural-kernel structural PDF must not be encrypted");
                COSDocument cosDocument = document.getDocument();
                require(cosDocument.isXRefStream(), "document does not use an xref stream");
                require(!cosDocument.hasHybridXRef(), "document uses a hybrid xref representation");
                COSDictionary trailer = cosDocument.getTrailer();
                require(COSName.XREF.equals(trailer.getCOSName(COSName.TYPE)),
                        "trailer dictionary is not the xref stream dictionary");
                require(trailer.getInt(COSName.SIZE) == expectedObjects + 1,
                        "xref /Size does not include exactly object zero and every object");
                COSBase root = trailer.getItem(COSName.ROOT);
                require(root instanceof COSObject && ((COSObject) root).getKey() != null
                                && ((COSObject) root).getKey().getNumber() == 1
                                && ((COSObject) root).getKey().getGeneration() == 0,
                        "xref /Root must be object 1 generation zero");
                validateIdentifier(trailer);
                pageTreeNodes = validateObjects(cosDocument, expectedObjects,
                        expectedPages, expectedPageTreeNodes);
                COSDictionary catalog = document.getDocumentCatalog().getCOSObject();
                require(COSName.CATALOG.equals(catalog.getCOSName(COSName.TYPE)),
                        "document catalog has the wrong /Type");
                facts = validatePages(document, expectedPages, expectedContentBytes,
                        expectedOperators);
            }
            catch (IOException exception)
            {
                throw new ValidationFailure("PDFBox object traversal failed", exception);
            }
            finally
            {
                try
                {
                    if (document != null)
                    {
                        document.close();
                    }
                    else if (source != null)
                    {
                        source.close();
                    }
                }
                catch (IOException exception)
                {
                    throw new ValidationFailure("PDFBox resource close failed", exception);
                }
            }
        }
        catch (java.io.UnsupportedEncodingException exception)
        {
            throw new ValidationFailure("UTF-8 is unavailable", exception);
        }
        finally
        {
            System.err.flush();
            System.setErr(originalError);
            rootLogger.removeHandler(warningHandler);
        }

        String diagnostics = new String(diagnosticBytes.toByteArray(), StandardCharsets.UTF_8).trim();
        require(warningHandler.warnings.isEmpty(),
                "PDFBox emitted warnings: " + String.join(" | ", warningHandler.warnings));
        require(diagnostics.isEmpty(), "PDFBox wrote diagnostics: " + diagnostics);
        System.out.println("PASS PDFBox " + implementationVersion() + " strict: " + path
                + ", pages=" + expectedPages + ", objects=" + expectedObjects
                + ", page_tree_nodes=" + pageTreeNodes + ", content_bytes=" + facts.contentBytes
                + ", operators=" + facts.operators + ", warnings=0, recovery=false");
    }

    public static void main(String[] args)
    {
        if (args.length != 6)
        {
            System.err.println("usage: StrictPdfCheck PDF PAGES OBJECTS PAGE_TREE_NODES CONTENT_BYTES OPERATORS");
            System.exit(64);
        }
        try
        {
            validateDocument(Path.of(args[0]),
                    parseExpected(args[1], "pages"),
                    parseExpected(args[2], "objects"),
                    parseExpected(args[3], "page-tree nodes"),
                    parseExpectedLong(args[4], "content bytes"),
                    parseExpectedLong(args[5], "operators"));
        }
        catch (StrictParseFailure failure)
        {
            System.err.println("FAIL PDFBox strict parse: " + failure.getMessage());
            System.exit(2);
        }
        catch (ValidationFailure failure)
        {
            System.err.println("FAIL PDFBox object assertions: " + failure.getMessage());
            System.exit(3);
        }
    }
}

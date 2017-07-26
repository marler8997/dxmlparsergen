import std.stdio : File, writeln, writefln;
import std.string : indexOf, countchars;
import std.format : format;
import std.conv : to;
import std.file : exists;
import std.xml : Document, Element, Tag;
import std.bigint : BigInt;

class SilentException : Exception
{
    this() { super(""); }
}

void usage()
{
    writeln("dxmlparsergen <xml-schema-file>");
}
int main(string[] args)
{
    args = args[1..$];
    if(args.length == 0)
    {
        usage();
        return 0;
    }
    if(args.length > 1)
    {
        writeln("Error: too many command line arguments");
        return 1;
    }
    string schemaFilename = args[0];
    if(!exists(schemaFilename))
    {
        writefln("Error: schema file \"%s\" does not exist", schemaFilename);
        return 1;
    }

    try
    {
        auto xmlSchema = XmlSchema(schemaFilename);
        if(xmlSchema.xmlRoot.tag.nameStripNamespace != "schema")
        {
            throw xmlSchema.exception(xmlSchema.xmlRoot, "expected root to be <schema> but is <%s>",
                xmlSchema.xmlRoot.tag.nameStripNamespace);
        }
        scope processor = new XmlSchemaProcessor(&xmlSchema);
        processor.processSchema(xmlSchema.xmlRoot);

        writeln("----------------------------------------------------------");
        writefln("there are %s types defined in the root context", processor.typeDefinitionMap.length);
        writeln("----------------------------------------------------------");
        foreach(typeDefinition; processor.typeDefinitionMap.byValue)
        {
            writefln("type \"%s\"", typeDefinition.name);
        }
        writeln("----------------------------------------------------------");
        writefln("there are %s root elements", processor.rootElementSchemas.length);
        writeln("----------------------------------------------------------");
        foreach(elementSchema; processor.rootElementSchemas)
        {
            writefln("<element name=\"%s\">", elementSchema.name);
        }

        return 0;
    }
    catch(SilentException e)
    {
        return 1;
    }
}

string readFile(const(char)[] filename)
{
    auto file = File(filename, "rb");
    auto filesize = file.size();
    if(filesize + 1 > size_t.max)
    {
        assert(0, filename ~ ": file is too large " ~ filesize.to!string ~ " > " ~ size_t.max.to!string);
    }
    auto contents = new char[cast(size_t)(filesize+1)]; // add 1 for '\0'
    auto readSize = file.rawRead(contents).length;
    assert(filesize == readSize, "rawRead only read " ~ readSize.to!string ~ " bytes of " ~ filesize.to!string ~ " byte file");
    contents[cast(size_t)filesize] = '\0';
    return cast(string)contents[0..$-1];
}
struct XmlSchema
{
    string filename;
    string fileContents;
    Document xmlRoot;

    this(string filename)
    {
        this.filename = filename;
        this.fileContents = readFile(filename);
        //std.xml.check(pbxmlString);
        this.xmlRoot = new Document(fileContents);
    }
    SilentException exception(T...)(Element element, string fmt, T args)
    {
        assert(element.tag.name.ptr >= fileContents.ptr &&
            element.tag.name.ptr <= (fileContents.ptr + fileContents.length));
        auto lineNumber = 1 + countchars(fileContents[0.. (element.tag.name.ptr-fileContents.ptr)], "\n");
        writefln("%s(%s) %s", filename, lineNumber, format(fmt, args));
        return new SilentException();
    }
    SilentException exception(T...)(string fmt, T args)
    {
        writefln("%s: %s", filename, format(fmt, args));
        return new SilentException();
    }
}


enum XmlSchemaPrimitiveType
{
    string_,
    decimal,
    integer,
    boolean,
    date,
    time,
}
enum XmlSchemaUse
{
    optional, prohibited, required,
}

auto nameStripNamespace(Tag tag)
{
    auto indexOfColon = tag.name.indexOf(':');
    if(indexOfColon >= 0)
    {
        return tag.name[indexOfColon + 1..$];
    }
    else
    {
        return tag.name;
    }
}


union SimpleValue
{
    string stringValue;
    string decimalValue;
    BigInt integerValue;
    bool booleanValue;
    string dateValue;
    string timeValue;
}

interface SchemaContext
{
    @property SchemaContext getParentContext();
    void addElementSchema(ElementSchema elementSchema);
    void addTypeDefinition(SchemaTypeDefinition typeDefinition);
}

class SchemaTypeReference
{
}

class SchemaTypeDefinition : SchemaContext
{
    SchemaContext parentContext;
    string name;
    ElementSchema[] childElements;
    SchemaTypeDefinition[] typeDefinitions;
    this(SchemaContext parentContext, Element xml)
    {
        this.parentContext = parentContext;
        this.name = xml.tag.attr.get("name", null);
    }
    final @property SchemaContext getParentContext() { return parentContext; }
    final void addElementSchema(ElementSchema elementSchema)
    {
        childElements ~= elementSchema;
    }
    final void addTypeDefinition(SchemaTypeDefinition typeDefinition)
    {
        typeDefinitions ~= typeDefinition;
    }
}
class SimpleTypeDefinition : SchemaTypeDefinition
{
    this(SchemaContext parentContext, Element xml)
    {
        super(parentContext, xml);
    }
}
class ComplexTypeDefinition : SchemaTypeDefinition
{
    ElementSchema[] sequence;
    attribute[] attributes;
    complexContent complexContent_;
    this(SchemaContext parentContext, Element xml)
    {
        super(parentContext, xml);
    }
}

class extension
{
    SchemaTypeReference base;
    ElementSchema[] sequence;
}

/* signals we intend to restrict or extend the content model of the complex type */
class complexContent
{
    extension extension_;
    restriction resetriction_;
}


/+
Restrictions for Datatypes
Constraint	Description
enumeration	Defines a list of acceptable values
fractionDigits	Specifies the maximum number of decimal places allowed. Must be equal to or greater than zero
length	Specifies the exact number of characters or list items allowed. Must be equal to or greater than zero
maxExclusive	Specifies the upper bounds for numeric values (the value must be less than this value)
maxInclusive	Specifies the upper bounds for numeric values (the value must be less than or equal to this value)
maxLength	Specifies the maximum number of characters or list items allowed. Must be equal to or greater than zero
minExclusive	Specifies the lower bounds for numeric values (the value must be greater than this value)
minInclusive	Specifies the lower bounds for numeric values (the value must be greater than or equal to this value)
minLength	Specifies the minimum number of characters or list items allowed. Must be equal to or greater than zero
pattern	Defines the exact sequence of characters that are acceptable
totalDigits	Specifies the exact number of digits allowed. Must be greater than zero
whiteSpace	Specifies how white space (line feeds, tabs, spaces, and carriage returns) is handled
+/
class restriction
{
}
class restriction_integer : restriction
{
    BigInt minInclusive;
    BigInt maxInclusive;
}
class restriction_string : restriction
{
    string[] enumerations;
}
class restriction_pattern : restriction
{
    string pattern;
}
class restriction_length : restriction
{
    BigInt value;
}
class restriction_lengths : restriction
{
    BigInt minLength;
    BigInt maxLength;
}

enum XmlSchemaWhitespace
{
    preserve, replace, collapse,
}
class restriction_whitespace : restriction
{
    XmlSchemaWhitespace value;
}

class ElementSchema : SchemaContext
{
    SchemaContext parentContext;
    this(SchemaContext parentContext)
    {
        this.parentContext = parentContext;
    }
    string name;
    SchemaTypeReference type;
    union
    {
        struct
        {
            // This field only applies if this element is a "simple type"
            SimpleValue simpleDefaultValue;
            SimpleValue simpleFixedValue;
        }
    }
    ElementSchema[] childElements;
    SchemaTypeDefinition[] typeDefinitions;

    @property SchemaContext getParentContext() { return parentContext; }
    final void addElementSchema(ElementSchema elementSchema)
    {
        childElements ~= elementSchema;
    }
    final void addTypeDefinition(SchemaTypeDefinition typeDefinition)
    {
        typeDefinitions ~= typeDefinition;
    }
}
class attribute
{
    string name;
    SchemaTypeReference type;
    union
    {
        struct
        {
            // This field only applies if this element is a "simple type"
            SimpleValue defaultValue;
            SimpleValue fixedValue;
        }
    }
    XmlSchemaUse use;
}


auto elementsWithNames(Element element)
{
    static struct NameAndElement
    {
        string name;
        Element xml;
    }
    static struct Iterator
    {
        Element* next;
        Element* limit;
        @property bool empty() { return next == limit; }
        @property auto front()
        {
            return NameAndElement(next.tag.nameStripNamespace, *next);
        }
        void popFront()
        {
            next++;
        }
    }
    return Iterator(element.elements.ptr, element.elements.ptr + element.elements.length);
}

class TemporaryDoNothingContext : SchemaContext
{
    SchemaContext parentContext;
    this(SchemaContext parentContext)
    {
        this.parentContext = parentContext;
    }
    @property SchemaContext getParentContext()
    {
        return parentContext;
    }
    final void addElementSchema(ElementSchema elementSchema)
    {
    }
    final void addTypeDefinition(SchemaTypeDefinition typeDefinition)
    {
    }
}

class XmlSchemaProcessor : SchemaContext
{
    XmlSchema* schema;

    SchemaTypeDefinition[string] typeDefinitionMap;
    ElementSchema[] rootElementSchemas;
    //Element[string] idTable;
    SchemaContext context;

    this(XmlSchema* schema)
    {
        this.schema = schema;
    }

    private static string contextMixin(string contextVariable)
    {
        return `
        this.context = ` ~ contextVariable ~ `;
        scope(exit)
        {
            assert(this.context is ` ~ contextVariable ~ `);
            this.context = context.getParentContext;
        }`;
    }
    enum temporaryContextMixin = `
        scope temporaryContext = new TemporaryDoNothingContext(context);
        this.context = temporaryContext;
        scope(exit)
        {
            assert(this.context is temporaryContext);
            this.context = temporaryContext.getParentContext;
        }`;

    auto requireAttribute(Element xml, string name, string contextDescription)
    {
        auto value = xml.tag.attr.get(name, null);
        if(value is null)
        {
            throw schema.exception(xml, "<%s> requires the \"%s\" attribute%s",
                xml.tag.nameStripNamespace, name, contextDescription);
        }
        return value;
    }
    void assertNoAttribute(Element xml, string name, string contextDescription)
    {
        auto value = xml.tag.attr.get(name, null);
        if(value !is null)
        {
            throw schema.exception(xml, "<%s> cannot have the \"%s\" attribute%s",
                xml.tag.nameStripNamespace, name, contextDescription);
        }
    }


    @property private bool inRootContext()
    {
        return context == this;
    }

    final @property SchemaContext getParentContext()
    {
        return null;
    }
    final void addElementSchema(ElementSchema elementSchema)
    {
        rootElementSchemas ~= elementSchema;
    }
    final void addTypeDefinition(SchemaTypeDefinition typeDefinition)
    {
        auto name = typeDefinition.name;
        if(name.length == 0)
        {
            throw schema.exception("all types must have a name if they are defined as direct children of <schema>");
        }
        auto existing = typeDefinitionMap.get(name, null);
        if(existing !is null)
        {
            throw schema.exception("multiple types named \"%s\"", name);
        }
        typeDefinitionMap[name] = typeDefinition;
    }

    void processSchema(Element xml)
    {
        assert(context is null);
        context = this;
        scope(exit)
        {
            assert(context is this);
            context = null;
        }

        foreach(child; xml.elementsWithNames)
        {
            if(child.name == "element")
            {
                processElement(child.xml);
            }
            else if(child.name == "complexType")
            {
                processComplexType(child.xml);
            }
            else if(child.name == "simpleType")
            {
                processSimpleType(child.xml);
            }
            else if(child.name == "annotation")
            {
                processAnnotation(child.xml);
            }
            else if(child.name == "notation")
            {
                processNotation(child.xml);
            }
            else if(child.name == "import")
            {
                // ignore for now???????????????
            }
            else if(child.name == "group")
            {
                processGroup(child.xml);
            }
            else if(child.name == "attributeGroup")
            {
                processAttributeGroup(child.xml);
            }
            else
            {
                throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
            }
        }
    }

    void processElement(Element xml)
    {
        auto elementSchema = new ElementSchema(context);
        if(inRootContext)
        {
            elementSchema.name = requireAttribute(xml, "name", " when it is a direct child of <schema>");
        }
        else
        {
            elementSchema.name = xml.tag.attr.get("name", null);
        }
        {
            mixin(contextMixin("elementSchema"));

            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "simpleType")
                {
                    processSimpleType(child.xml);
                }
                else if(child.name == "complexType")
                {
                    processComplexType(child.xml);
                }
                else if(child.name == "key")
                {
                    processKey(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }

        context.addElementSchema(elementSchema);
    }
    void processAttributeGroup(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "attribute")
                {
                    processAttribute(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processGroup(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else if(child.name == "choice")
                {
                    processChoice(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processChoice(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "group")
                {
                    processGroup(child.xml);
                }
                else if(child.name == "any")
                {
                    processAny(child.xml);
                }
                else if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "element")
                {
                    processElement(child.xml);
                }
                else if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processNotation(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "!!!!!")
                {
                    // ignore it
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processAnnotation(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "documentation")
                {
                    // ignore it for now
                }
                else if(child.name == "appinfo")
                {
                    // ignore it for now
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processSimpleType(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "restriction")
                {
                    processRestriction(child.xml);
                }
                else if(child.name == "list")
                {
                    processList(child.xml);
                }
                else if(child.name == "union")
                {
                    processUnion(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processComplexType(Element xml)
    {
        auto complexType = new ComplexTypeDefinition(context, xml);
        {
            mixin(contextMixin("complexType"));

            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "simpleContent")
                {
                    processSimpleContent(child.xml);
                }
                else if(child.name == "complexContent")
                {
                    processComplexContent(child.xml);
                }
                else if(child.name == "all")
                {
                    processAll(child.xml);
                }
                else if(child.name == "attribute")
                {
                    processAttribute(child.xml);
                }
                else if(child.name == "anyAttribute")
                {
                    // ignore it for now
                }
                else if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
        context.addTypeDefinition(complexType);
    }

    void processSimpleContent(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "restriction")
                {
                    processRestriction(child.xml);
                }
                else if(child.name == "extension")
                {
                    processExtension(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processComplexContent(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "extension")
                {
                    processExtension(child.xml);
                }
                else if(child.name == "restriction")
                {
                    processRestriction(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processExtension(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else if(child.name == "choice")
                {
                    processChoice(child.xml);
                }
                else if(child.name == "group")
                {
                    processGroup(child.xml);
                }
                else if(child.name == "attribute")
                {
                    processAttribute(child.xml);
                }
                else if(child.name == "attributeGroup")
                {
                    processAttributeGroup(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processAttribute(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "simpleType")
                {
                    processSimpleType(child.xml);
                }
                else if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processSequence(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "element")
                {
                    processElement(child.xml);
                }
                else if(child.name == "any")
                {
                    processAny(child.xml);
                }
                else if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "choice")
                {
                    processChoice(child.xml);
                }
                else if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else if(child.name == "group")
                {
                    processGroup(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processAny(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processAll(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "element")
                {
                    processElement(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processUnion(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "simpleType")
                {
                    processSimpleType(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processList(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "simpleType")
                {
                    processSimpleType(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }

    void processKey(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "selector")
                {
                    // ignore for now
                }
                else if(child.name == "field")
                {
                    // ignore for now
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
    void processRestriction(Element xml)
    {
        {
            mixin(temporaryContextMixin);
            foreach(child; xml.elementsWithNames)
            {
                if(child.name == "anyAttribute")
                {
                    // ignore for now
                }
                else if(child.name == "minLength")
                {
                    // ignore for now
                }
                else if(child.name == "maxLength")
                {
                    // ignore for now
                }
                else if(child.name == "minInclusive")
                {
                    // ignore for now
                }
                else if(child.name == "maxInclusive")
                {
                    // ignore for now
                }
                else if(child.name == "fractionDigits")
                {
                    // ignore for now
                }
                else if(child.name == "enumeration")
                {
                    // ignore for now
                }
                else if(child.name == "pattern")
                {
                    // ignore for now
                }
                else if(child.name == "whiteSpace")
                {
                    // ignore for now
                }
                else if(child.name == "simpleType")
                {
                    processSimpleType(child.xml);
                }
                else if(child.name == "group")
                {
                    processGroup(child.xml);
                }
                else if(child.name == "annotation")
                {
                    processAnnotation(child.xml);
                }
                else if(child.name == "attribute")
                {
                    processAttribute(child.xml);
                }
                else if(child.name == "sequence")
                {
                    processSequence(child.xml);
                }
                else
                {
                    throw schema.exception(child.xml, "unknown element <%s> (context=<%s>)", child.name, xml.tag.name);
                }
            }
        }
    }
}
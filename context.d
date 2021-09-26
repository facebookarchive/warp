
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module context;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import std.algorithm;
import std.array;
import std.path;
import std.range;
import std.stdio;
import std.traits;

import cmdline;
import directive;
import expanded;
import id;
import lexer;
import loc;
import macros;
import util;
import outdeps;
import textbuf;
import sources;

/*********************************
 * Keep the state of the preprocessor in this struct.
 * Input:
 *      R       output range for preprocessor output
 */

//debug=ContextStats;

struct Context(R)
{
    SourceStack stack;
    Expanded!R expanded;         // for expanded (preprocessed) output

    const Params params;      // command line parameters

    const string[] paths;     // #include paths
    const size_t sysIndex;    // paths[sysIndex] is start of system #includes

    private bool errors;        // true if any errors occurred
    private __gshared uint counter;       // for __COUNTER__

    bool doDeps;        // true if doing dependency file generation
    string[] deps;      // dependency file contents

    private Source* psourceFile;

    debug (ContextStats)
    {
        int sourcei;
        int sourceimax;
    }

    // Used in the implementation of overrideIncludeTrace;
    LocList* overriddenIncludeTrace;

    // Used in the implementation of overrideLoc().
    Loc overriddenLoc;

    Loc lastloc;
    bool uselastloc;

    __gshared Context* _ctx;            // shameful use of global variable
    //Context* prev;                      // previous one in stack of these

    // Stack of #if/#else/#endif nesting
    ubyte[64] tmpbuf = void;
    Textbuf!(ubyte,"ifs") ifstack;


    /******
     * Construct global context from the command line parameters
     */
    this(ref const Params params)
    {
        this.params = params;
        this.doDeps = params.depFilename.length != 0;

        string[] pathsx;
        size_t sysIndexx;
        combineSearchPaths(params.includes,
                           params.sysincludes,
                           pathsx,
                           sysIndexx);
        paths = pathsx;         // workaround for Bugzilla 11743
        sysIndex = sysIndexx; // workaround for Bugzilla 11743
        ifstack = Textbuf!(ubyte,"ifs")(tmpbuf);
        ifstack.initialize();
        expanded.initialize(&this);
        setContext();
    }

    /**************************************
     * Returns a LocList representing the #include directives leading up
     * to the inclusion of the current source code. The first element of
     * the list corresponds to the most deeply nested include directive.
     * The return value of this function may be null, which represents
     * the empty list.
     */
    LocList* includeTrace()
    {
        if (overriddenIncludeTrace != overriddenIncludeTrace.init) {
            return overriddenIncludeTrace;
        }
        auto csf = currentSourceFile();
        if (csf) return csf.includeTrace;
        return null;
    }

    /**************************************
     * When called with a non-null value, causes includeTrace() to return
     * that value instead of its normal return value.
     */
    void overrideIncludeTrace(LocList* trace)
    {
        overriddenIncludeTrace = trace;
    }

    /**************************************
     * When called with a value other than Loc.init, causes loc() to return
     * that value instead of its normal return value.
     */
    void overrideLoc(Loc loc)
    {
        overriddenLoc = loc;
    }

    /**************************************
     * Create a new Context on a stack of them.
     */
    Context* pushContext()
    {
        auto st = SourceStack.allocate();
        auto root = st.psourceRoot;
        *st = stack;
        stack = stack.init;
        stack.psourceRoot = root;
        stack.prev = st;
        return &this;
    }

    Context* popContext()
    {
        auto root = stack.psourceRoot;
        auto p = stack.prev;
        stack = *stack.prev;
        p.psourceRoot = root;
        p.deallocate();
        return &this;
    }

    /***************************
     * Reset to use again.
     */
    void reset()
    {
        Id.reset();
        SrcFile.reset();

        counter = 0;
        ifstack.initialize();
        stack.xc = ' ';
        lastloc = lastloc.init;
        uselastloc = false;
        stack.psource = null;
    }

    static Context* getContext()
    {
        return _ctx;
    }

    void setContext()
    {
        _ctx = &this;
    }

    /**********
     * Create local context
     */
    void localStart(SrcFile* sf, R* outrange)
    {
        // Define predefined macros
        Id.defineMacro(cast(ustring)"__BASE_FILE__", null, cast(ustring)sf.filename, Id.IDpredefined);
        Id.initPredefined();
        foreach (def; params.defines)
            macrosDefine(cast(ustring)def);

        // Set up preprocessed output
        expanded.start(outrange);

        // Initialize source text
        pushFile(sf, Sys.none, -1, null);

        version (unittest)
        {
            // Don't make unittest results unnecessarily complicated
        }
        else
        {
            if (auto s = currentSourceFile())
            {
                // Output a prolog the way gcc does (in particular
                // contains directory information that may be helping gdb
                // locate sources).
                import std.file, std.format;
                outrange.formattedWrite(
                    //"# 1 \"%1$s\"\n" Written by pushFile
                    "# 1 \"%2$s//\"\n" ~
                    "# 1 \"<command-line>\"\n" ~
                    "# 1 \"%1$s\"\n",
                    s.loc.srcFile.filename, getcwd);
            }
        }
    }

    void pushFile(SrcFile* sf, Sys system, int pathIndex, LocList* includeTrace)
    {
        //write("pushFile ", pathIndex);
        auto s = push();
        s.includeTrace = includeTrace;
        psourceFile = s;
        s.addFile(sf, system, pathIndex);

        // insert a line directive for start-of-file
        // linemarker decrements lineNumber when writing, so set to 2
        Loc tmploc = s.loc;
        tmploc.lineNumber = 2;
        tmploc.linemarker(expanded.foutr);

        if (lastloc.srcFile)
            uselastloc = true;
        assert(s.ptext);
    }

    /**********
     * Preprocess a file
     */
    void preprocess()
    {
        auto lexer = createLexer(&this);
        while (1)
        {
            // Either at start of a new line, or the end of the file
            assert(!lexer.empty);
            auto tok = lexer.front;
            if (tok == TOK.eol)
                lexer.popFront();
            else if (tok == TOK.hash)
            {
                // A '#' starting off a line says preprocessing directive
                if (lexer.parseDirective())
                {
                    auto csf = currentSourceFile();
                    if (csf)
                    {
                        csf.seenTokens = true;
                    }
                }
            }
            else if (tok == TOK.eof)
                break;
            else
            {
                auto csf = currentSourceFile();
                if (csf)
                {
                    csf.seenTokens = true;
                }

                do
                {
                    lexer.popFront();
                } while (lexer.front != TOK.eol);
                lexer.popFront();
            }
        }
    }

    /**********
     * Finish local context
     */
    void localFinish()
    {
        expanded.finish();

        debug (ContextStats)
        {
            writefln("max Source depth = %d", sourceimax);
        }
    }

    /**********
     * Finish global context
     */
    void globalFinish()
    {
        if (doDeps && !errors)
        {
            dependencyFileWrite(params.depFilename, deps);
        }
    }

    @property bool empty()
    {
        return stack.xc == stack.xc.init;
    }

    @property uchar front()
    {
        return stack.xc;
    }

    void popFront()
    {
        auto s = stack.psource;
        if (s.ptext.length)
        {
            auto c = s.ptext[0];
            stack.xc = c;
            s.ptext = s.ptext[1 .. $];
            expanded.put(c);
        }
        else
            popFront2();
    }

    void popFront2()
    {
        while (1)
        {
            auto s = stack.psource;
            if (s.ptext.length == 0)
            {
                if (s.isFile && !s.input.empty)
                {
                    s.readLine();
                    continue;
                }
                ++s.loc.lineNumber;
                s = pop();
                if (s)
                    continue;
                stack.xc = stack.xc.init;
                break;
            }
            else
            {
                stack.xc = s.ptext[0];
                s.ptext = s.ptext[1 .. $];
            }
            expanded.put(stack.xc);
            break;
        }
    }

    uchar[] lookAhead()
    {
        return stack.psource.ptext[];
    }

    void popFrontN(size_t n)
    {
        auto s = stack.psource;
        s.ptext = s.ptext[n .. $];
    }

    uchar[] restOfLine()
    {
        auto s = stack.psource;
        auto result = s.ptext[];
        s.ptext = s.ptext[result.length .. result.length];
        stack.xc = '\n';
        return result;
    }

    void unget()
    {
        auto s = stack.psource;
        if (s)
            push(stack.xc);
    }

    void push(uchar c)
    {
        auto s = push();
        s.smallString[0] = c;
        s.ptext = s.smallString[];
    }

    void push(const(uchar)[] str)
    {
        if (str.length == 1)
            push(str[0]);
        else
        {
            auto s = push();
            s.lineBuffer.initialize();
            s.lineBuffer.put(str);
            s.ptext = s.lineBuffer[0 .. str.length];
        }
    }

    Source* currentSourceFile()
    {
        return psourceFile;
    }

    Loc loc()
    {
        if (overriddenLoc != overriddenLoc.init)
            return overriddenLoc;
        auto csf = currentSourceFile();
        if (csf)
            return csf.loc;
        if (lastloc.srcFile)
            return lastloc;
        Loc loc;
        return loc;
    }

    Source* push()
    {
        auto s = stack.psource;
        if (s)
        {
            s = s.next;
            if (!s)
            {
                // Ran out of space, allocate another chunk
                auto sources2 = new Source[16];
                Source.initialize(sources2, stack.psource, &stack.psource.next);
                s = stack.psource.next;
                assert(s);
            }
        }
        else
        {
            if (!stack.psourceRoot)
            {
                auto sources2 = new Source[16];
                Source.initialize(sources2, stack.psource, &stack.psource);
                stack.psourceRoot = sources2.ptr;
            }
            s = stack.psourceRoot;
        }
        s.isFile = false;
        s.isExpanded = false;
        s.seenTokens = false;
        stack.psource = s;

        debug (ContextStats)
        {
            ++sourcei;
            if (sourcei > sourceimax)
                sourceimax = sourcei;
        }

        return s;
    }

    Source* pop()
    {
        auto s = stack.psource;
        if (s.isFile)
        {
            // Back up and find previous file; null if none
            if (psourceFile == s)
            {
                for (auto ps = s; 1;)
                {
                    ps = ps.prev;
                    if (!ps || ps.isFile)
                    {
                        psourceFile = ps;
                        break;
                    }
                }
            }
            lastloc = s.loc;
            uselastloc = true;
            if (s.includeGuard && !s.seenTokens)
            {
                // Saw #endif and no tokens
                s.loc.srcFile.includeGuard = s.includeGuard;
            }
        }
        stack.psource = stack.psource.prev;
        debug (ContextStats)
        {
            --sourcei;
        }
        return stack.psource;
    }

    int nestLevel()
    {
        int level = -1;
        auto csf = currentSourceFile();
        while (csf)
        {
            if (csf.isFile)
                ++level;
            csf = csf.prev;
        }
        return level;
    }

    bool isExpanded() { return stack.psource.isExpanded; }

    void setExpanded() { stack.psource.isExpanded = true; }

    /***************************
     * Push predefined macro text into input.
     */
    void pushPredefined(Id* m)
    {
        Loc loc;
        if (auto s = currentSourceFile())
            loc = s.loc;
        else
            loc = lastloc;
        if (!loc.srcFile)
            return;

        uint n;

        switch (m.flags & (Id.IDlinnum | Id.IDfile | Id.IDcounter))
        {
            case Id.IDlinnum:
                n = loc.lineNumber;
                break;

            case Id.IDfile:
            {
                auto s = push();
                s.lineBuffer.initialize();
                s.lineBuffer.put('"');
                s.lineBuffer.put(cast(ustring)loc.fileName);
                s.lineBuffer.put('"');
                s.ptext = s.lineBuffer[];
                return;
            }

            case Id.IDcounter:
                n = counter++;
                break;

            default:
                assert(0);
        }
        uchar[counter.sizeof * 3 + 1] buf;
        auto len = sprintf(cast(char*)buf.ptr, "%u", n);
        assert(len > 0);
        push(cast(ustring)buf[0 .. len]);
    }

    /*******************************************
     * Search for file along paths[]
     * Input:
     *  s               file to search for (in a temp buffer)
     *  sysstring       if <file>
     *  system          system status of the the file doing the #include
     *  currentFile     file name of file doing the #include
     *  pathIndex       index of file doing the #include
     * Output:
     *  pathIndex       index of where file was found
     *  system          new value for found file
     */
    SrcFile* searchForFile(bool includeNext, bool sysstring, ref Sys system,
        const(char)[] s,
        ref int pathIndex, string currentFile)
    {
        //writefln("searchForFile(includeNext = %s, system = %s, s = '%s')", includeNext, system, s);
        //writefln("paths = [%s]", paths);

        string currentPath = null;
        if (!sysstring && !includeNext)
            currentPath = dirName(currentFile);

        if (includeNext)
            ++pathIndex;
        else
        {
            if (system || sysstring)
                pathIndex = 1;          // skip current working directory, which is always first
            else
                pathIndex = 0;
        }

        auto sf = fileSearch(s, paths, pathIndex, pathIndex, currentPath);
        if (!sf)
            return null;

        //writefln("pathIndex = %d sysIndex = %d length = %d", pathIndex, sysIndex, paths.length);
        if (pathIndex >= sysIndex && pathIndex < paths.length)
            system |= Sys.syspath;      // |= because bit is transitive

        /* Do not add to dependencies files that are found in system header directories,
         * or are transitively included from such a header.
         * "" or < > status has no bearing on dep generation.
         */

        if (!sf.cachedRead && doDeps && !(system & Sys.syspath))
            deps ~= sf.filename;

        return sf;
    }
}


/*************************************************
 * Determine if range r is an instance of Context
 */

template isContext(R)
{
    enum bool isContext = __traits(hasMember, R, "stack");
}

/*************************************************
 * Stack of Source's
 */

struct SourceStack
{
    Source* psource;
    uchar xc = ' ';
    SourceStack* prev;
    Source* psourceRoot;

    __gshared SourceStack* _freelist;

    static SourceStack* allocate()
    {
        auto st = _freelist;
        if (st)
        {
            _freelist = st.prev;
        }
        else
        {
            st = cast(SourceStack*)malloc(SourceStack.sizeof);
            assert(st);
            *st = SourceStack.init;
        }
        return st;
    }

    void deallocate()
    {
        prev = _freelist;
        _freelist = &this;
    }

    @property bool empty()
    {
        return xc == xc.init;
    }

    @property uchar front()
    {
        return xc;
    }

    void popFront()
    {
        auto s = psource;
        if (s.ptext.length)
        {
            xc = s.ptext[0];
            s.ptext = s.ptext[1 .. $];
        }
        else
            popFront2();
    }

    void popFront2()
    {
        while (1)
        {
            auto s = psource;
            if (s.ptext.length)
            {
                xc = s.ptext[0];
                s.ptext = s.ptext[1 .. $];
            }
            else
            {
                if (s.isFile && !s.input.empty)
                {
                    s.readLine();
                    continue;
                }
                ++s.loc.lineNumber;
                s = pop();
                if (s)
                    continue;
                xc = xc.init;
                break;
            }
            break;
        }
    }

    Source* pop()
    {
        assert(!psource.isFile);
        psource = psource.prev;
        return psource;
    }
}

/******************************************
 * Source text.
 */

struct Source
{
    Textbuf!(uchar,"src") lineBuffer = void;

    LocList* includeTrace;

    uchar[] ptext;

    uchar[1] smallString; // for 1 character buffers
    bool isFile;        // if it is a file
    bool isExpanded;    // true if already macro expanded
    bool seenTokens;    // true if seen tokens

    // Double linked list of stack of Source's
    Source* prev;
    Source* next;

    // These are if isFile is true
    Loc loc;            // current location
    ustring input;      // remaining file contents
    ustring includeGuard;
    int pathIndex;      // index into paths[] of where this file came from (-1 if not)
    int ifstacki;       // index into ifstack[]

    uchar[256] tmpbuf = void;

    /*****
     * Instead of constructing them individually, do them as a group,
     * necessary to sew together the linked list.
     */
    static void initialize(Source[] sources, Source* prev, Source** pNext)
    {
        foreach (ref src; sources)
        {
            src.prev = prev;
            prev = &src;

            if (pNext)
                *pNext = &src;
            pNext = &src.next;
            src.next = null;

            src.lineBuffer = Textbuf!(uchar,"src")(src.tmpbuf);
        }
    }

    void addFile(SrcFile* sf, Sys system, int pathIndex)
    {
        // set new file, set haven't seen tokens yet
        loc.srcFile = sf;
        loc.fileName = sf.filename;
        loc.lineNumber = 0;
        loc.system = system;
        input = sf.contents;
        isFile = true;
        includeGuard = null;
        this.pathIndex = pathIndex;
        this.isExpanded = false;
        this.seenTokens = false;
        readLine();
    }

    /***************************
     * Read next line from input[] and store in lineBuffer[].
     * Do \ line splicing.
     */
    void readLine()
    {
        //writefln("Source.readLine() %d", loc.lineNumber);
        if (!input.empty)
        {
            ++loc.lineNumber;

            immutable(uchar)* p;
            for (p = input.ptr; *p != '\n'; ++p)
            {
                if (*cast(byte*)p < 0 && (*p == ESC.space || *p == ESC.brk))
                    goto L1;
            }

            if (p[-1] == '\\' ||             // SPAD ensures we can look behind
                p[-1] == '\r' && p[-2] == '\\')
            {
             L1:
                readLineEsc();
            }
            else
            {
                auto len = p - input.ptr + 1;
                ptext = cast(uchar[])input[0 .. len];
                input = input[len .. $];
            }
        }
    }

    /**********************
     * Same as readLine(), but ESC.space and ESC.brk need to be
     * encoded as 0xFX.  This should be fine as raw binary data is
     * only meaningful inside string or character literals, where 00
     * is already encoded.
     */
    void readLineEsc()
    {
        lineBuffer.initialize();
        while (!input.empty)
        {
            while (1)
            {
                uchar c = input[0];
                input = input[1 .. $];
                switch (c)
                {
                    case '\n':
                        lineBuffer.put(c);
                        break;

                    case ESC.space:
                    case ESC.brk:
                        lineBuffer.put(cast(ustring)"\\37");
                        c = (c & 7) + '0';
                        goto default;

                    default:
                        lineBuffer.put(c);
                        continue;
                }
                break;
            }
            auto len = lineBuffer.length;
            uchar c = void;
            if (len >= 2 &&
                ((c = lineBuffer[len - 2]) == '\\' ||
                 (c == '\r' && len >= 3 && lineBuffer[len - 3] == '\\')))
            {
                if (c == '\r')
                    lineBuffer.pop();
                lineBuffer.pop();
                lineBuffer.pop();
                ++loc.lineNumber;
            }
            else
                break;
        }
        ptext = lineBuffer[];

        assert(lineBuffer.length && lineBuffer[lineBuffer.length - 1] == '\n');
        //writefln("\t%d", loc.lineNumber);
    }
}

/************************************** unit tests *************************/

version (unittest)
{
    void testPreprocess(const Params params, string src, string result)
    {

        uchar[100] tmpbuf = void;
        auto outbuf = Textbuf!uchar(tmpbuf);

        auto context = Context!(Textbuf!uchar)(params);

        // Create a fake source file with contents
        auto sf = SrcFile.lookup("test.c");
        sf.contents = cast(ustring)src;

        context.localStart(sf, &outbuf);

        context.preprocess();

        context.expanded.finish();
        if (outbuf[] != result)
            writefln("output = |%s|", cast(string)(outbuf[]));
        assert(outbuf[] == result);
    }
}

version (all)
{
unittest
{
    const Params params;
    testPreprocess(params,
"asdf\r
asd\\\r
ff\r
",

`# 1 "test.c"
# 2 "test.c"
asdf
# 3 "test.c"
asdff
`);
}

unittest
{
    writeln("u2");
    Params params;
    params.defines ~= "abc=def";
    testPreprocess(params, "+abc+\n",
                   "# 1 \"test.c\"\n# 1 \"test.c\"\n+def+\n");
}
}

unittest
{
    writeln("u3");
    Params params;
    params.defines ~= "abc2(a)=def=a=*";
    testPreprocess(params, "+abc2(3)+\n",
                   "# 1 \"test.c\"\n# 1 \"test.c\"\n+def=3=* +\n");
//    exit(0);
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */

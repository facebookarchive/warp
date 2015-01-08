
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module outdeps;

import std.stdio;
import std.path;
import std.range;

import textbuf;

version (Windows)
    immutable string extObj = "obj";
else
    immutable string extObj = "o";

/***************************************
 * Format dependencies into OutputRange r.
 * Formatting is separated from file writing so the former can be unittested.
 */

R dependencyFileFormat(R)(ref R r, string[] deps) if (isOutputRange!(R, char))
{
    void puts(string s)
    {
        foreach (char c; s)
            r.put(c);
    }

    void putln() { r.put('\n'); }

    if (deps.length)
    {
        int col = 1;

        string objfilename = setExtension(deps[0], extObj);
        puts(objfilename);
        puts(": ");
        col += objfilename.length + 2;

        foreach (dep; deps)
        {
            if (col >= 70)
            {
                puts(" \\");
                putln();
                col = 1;
            }
            r.put(' ');
            puts(dep);
            col += 1 + dep.length;
        }
        if (col > 1)
            putln();
    }
    return r;
}


unittest
{
    string[] deps = ["asdfasdf.d", "kjjksdkfj.d", "asdkjfksdfj.d",
                     "asdfasdf0.d", "kjjksdkfj0.d", "asdkjfksdfj0.d",
                     "asdfasdf1.d", "kjjksdkfj1.d", "asdkjfksdfj1.d",
                ];

    char[1000] buf;
    auto textbuf = Textbuf!char(buf);

    textbuf.dependencyFileFormat(deps);
    auto r = textbuf[0 .. textbuf.length];
    //writefln("|%s|", r);
    assert(r ==
"asdfasdf." ~ extObj ~ ":  asdfasdf.d kjjksdkfj.d asdkjfksdfj.d asdfasdf0.d kjjksdkfj0.d \\
 asdkjfksdfj0.d asdfasdf1.d kjjksdkfj1.d asdkjfksdfj1.d
");
    textbuf.free();
}


/*************************************
 * Write dependencies to filename.
 */
void dependencyFileWrite(string filename, string[] deps)
{
    auto f = File(filename, "w");
    auto w = f.lockingTextWriter();
    dependencyFileFormat(w, deps);
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */

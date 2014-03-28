
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module loc;

import std.format;
import std.stdio;

import sources;

/*************************************
 * Current location.
 */

struct Loc
{
    SrcFile* srcFile;
    uint lineNumber;    // line number of current position
    bool isSystem;      // true if system file

    /********************************************
     * Write out linemarker for current location to range r.
     */
    void linemarker(R)(R r)
    {
        r.formattedWrite("# %d \"%s\"", lineNumber - 1, srcFile.filename);
        if (isSystem)
        {
            r.put(' ');
            /* Values are:
             *    1  start of file
             *    2  return to this file
             *    3  system file
             *    4  file should be wrapped in implicit extern "C"
             */
            r.put('3');
        }
        r.put('\n');
    }

    /**********************************************
     * Write out current location to File*
     */
    void write(File* f)
    {
        //writefln("%s(%s) %s", srcFile ? srcFile.filename : "", lineNumber, isSystem);
        if (srcFile)
            f.writef("%s(%d) : ", srcFile.filename, lineNumber);
    }
}



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
 * Flags that indicate system file status.
 */

enum Sys : ubyte
{
    none = 0,     // not a system file
    angle = 1,    // #include'd with < >
    syspath = 2,  // appears in --isystem path, or was #include'd from a Sys.syspath file
}

/*************************************
 * Current location.
 */

struct Loc
{
    SrcFile* srcFile;
    string fileName;    // because #line may change the filename
    uint lineNumber;    // line number of current position
    Sys system;        // system file status

    /********************************************
     * Write out linemarker for current location to range r.
     */
    void linemarker(R)(R r)
    {
        r.formattedWrite("# %d \"%s\"", lineNumber - 1, fileName);
        if (system)
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
        //writefln("%s(%s) %s", fileName, lineNumber, system);
        if (srcFile)
            f.writef("%s:%d: ", fileName, lineNumber);
    }
}

/*************************************************
 * Element of a linked list of locations.
 */
struct LocList
{
    Loc first;
    LocList* rest;
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */

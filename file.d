// Written in the D programming language.
// This is derived from phobos/std/file.d, with a rewrite of the file reader.

/**
Utilities for manipulating files and scanning directories. Functions
in this module handle files as a unit, e.g., read or write one _file
at a time. For opening files and manipulating them via handles refer
to module $(LINK2 std_stdio.html,$(D std.stdio)).

Macros:

Copyright: Copyright Digital Mars 2007 - 2011.
License:   $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   $(LINK2 http://digitalmars.com, Walter Bright),
           $(LINK2 http://erdani.org, Andrei Alexandrescu),
           Jonathan M Davis
 */
module file;

import std.file;
import core.memory;
import core.stdc.stdio, core.stdc.stdlib, core.stdc.string,
       core.stdc.errno, std.algorithm, std.array, std.conv,
       std.datetime, std.exception, std.format, std.path, std.process,
       std.range, std.stdio, std.string, std.traits,
       std.typecons, std.typetuple, std.utf;


version (Windows)
{
    import core.sys.windows.windows, std.windows.syserror;
}
else version (Posix)
{
    import core.sys.posix.dirent, core.sys.posix.fcntl, core.sys.posix.sys.stat,
        core.sys.posix.sys.time, core.sys.posix.unistd, core.sys.posix.utime;
}
else
    static assert(false, "Module " ~ .stringof ~ " not implemented for this OS.");



/********************************************
Read entire contents of file $(D name) and returns it as an untyped
array. If the file size is larger than $(D upTo), only $(D upTo)
bytes are read.

Returns: Untyped array of bytes _read.
        null if file doesn't exist.

 */

/* With or without this on Windows things might be faster - I get ambiguous results
 */
//version = onestat;

void[] myRead(in char[] name, size_t upTo = size_t.max)
{
    version(Windows)
    {
        auto namez = std.utf.toUTF16z(name);

        /* Doing a stat to see if the file is there before attempting to read it
         * turns out to be much faster.
         */
        version (onestat)
        {
            WIN32_FILE_ATTRIBUTE_DATA fad;
            if (GetFileAttributesExW(namez, GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard, &fad) == 0)
                return null;
            if (fad.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                return null;

            ULARGE_INTEGER li;
            li.LowPart = fad.nFileSizeLow;
            li.HighPart = fad.nFileSizeHigh;
            auto size = cast(size_t)li.QuadPart;
        }
        else
        {   // Two stats
            auto attr = GetFileAttributesW(namez);
            if (attr == 0xFFFF_FFFF || attr & FILE_ATTRIBUTE_DIRECTORY)
                return null;
        }

        alias TypeTuple!(GENERIC_READ,
                FILE_SHARE_READ, (SECURITY_ATTRIBUTES*).init, OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
                HANDLE.init)
            defaults;
        auto h = CreateFileW(namez, defaults);

        if (h == INVALID_HANDLE_VALUE)
            return null;
        scope(exit) CloseHandle(h);

        version (statsize)
        {
        }
        else
        {
            auto size = GetFileSize(h, null);
            if (size == INVALID_FILE_SIZE)
                return null;
        }

        size = min(upTo, size);
        auto buf = malloc(size + 1);
        assert(buf);

        DWORD numread = void;
        if (ReadFile(h, buf, size, &numread, null) != 1
                || numread != size)
        {
            free(buf);
            return null;
        }

        (cast(ubyte*)buf)[size] = 0;            // sentinel at end
        return buf[0 .. size];
    }
    else version(Posix)
    {
        auto namez = toStringz(name);

        /* Doing a stat to see if the file is there before attempting to read it
         * turns out to be much faster.
         */
        stat_t statbuf = void;
        if (stat(namez, &statbuf) != 0 ||
            (statbuf.st_mode & S_IFMT) != S_IFREG)
            return null;

        // A few internal configuration parameters {
        enum size_t
            minInitialAlloc = 1024 * 4,
            maxInitialAlloc = size_t.max / 2,
            sizeIncrement = 1024 * 16,
            maxSlackMemoryAllowed = 1024;
        // }

        immutable fd = core.sys.posix.fcntl.open(namez,
                core.sys.posix.fcntl.O_RDONLY);
        if (fd == -1)
            return null;

        scope(exit) core.sys.posix.unistd.close(fd);

        immutable initialAlloc = to!size_t(statbuf.st_size
            ? min(statbuf.st_size + 1, maxInitialAlloc)
            : minInitialAlloc);

        auto result = malloc(initialAlloc + 1);
        assert(result);
        size_t result_length = initialAlloc;
        size_t size = 0;

        for (;;)
        {
            immutable actual = core.sys.posix.unistd.read(fd, result + size,
                    min(result_length, upTo) - size);
            if (actual == -1)
            {
                free(result);
                return null;
            }
            if (actual == 0) break;
            size += actual;
            if (size < result_length) continue;
            immutable newAlloc = size + sizeIncrement;
            result = realloc(result, newAlloc + 1);
            assert(result);
            result_length = newAlloc;
        }

        result = result_length - size >= maxSlackMemoryAllowed
            ? realloc(result, size + 1)
            : result;

        (cast(ubyte*)result)[size] = 0;            // sentinel at end
        return result[0 .. size];
    }
    else
        static assert(0);
}

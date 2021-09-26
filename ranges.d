
/****
 * Generic ranges not found in Phobos.
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module ranges;

/**************
 * BitBucket is an OutputRange that throws away its output.
 */

struct BitBucket(E)
{
    static void put(E e) { }
}

/*****************************************
 */

struct EmptyInputRange(E)
{
    enum bool empty = true;

    enum E front = E.init;

    static void popFront() { assert(0); }
}

/*****************************************
 */

struct StaticArrayBuffer(E, size_t N)
{
    size_t i;
    E[N] arr = void;

    void initialize() { i = 0; }

    void put(E e)
    {
        if (i >= N) {
          detectedOverflow();
        }
        arr[i] = e;
        ++i;
    }

    void put(E[] e)
    {
        if (i + e.length >= N + 1) {
            detectedOverflow();
        }
        arr[i .. i + e.length] = e[];
        i += e.length;
    }

    E[] opSlice()
    {
        return arr[0 .. i];
    }

    @property size_t length() { return i; }

 private:
    void detectedOverflow() {
      import util;
      err_fatal("Buffer overflowed. Possibly caused by forgetting to " ~
          "complete a git merge in your code.");
    }
}


//import std.stdio;

unittest
{
    StaticArrayBuffer!(ubyte, 2) buf = void;
    buf.initialize();
    buf.put('a');
    buf.put('b');
//writefln("'%s'", buf.get());
    assert(buf[] == "ab");
}

unittest
{
    ubyte[2] buf = void;
    size_t i;
    buf[i] = 'a';
    ++i;
    buf[i] = 'b';
    ++i;
    assert(buf[0 .. i] == "ab");
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */

/**
 * C preprocessor
 * Copyright: 2013-2014 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module charclass;

import std.ascii;

import util;

/*****************************************
 * Use an array lookup to determine what kind of character it is;
 * the array should remain hot in the cache.
 */

enum CClass
{
    identifierStart = 1,
    identifierChar  = 2,
    separator       = 4,
    multiTok        = 8,
}

immutable ubyte[256] cclassTable;

/******************************************
 * Characters that make up the start of an identifier.
 */

static this()
{
    for (uint c = 0; c < 0x100; ++c)
    {
        if (isAlpha(c) || c == '_')
            cclassTable[c] |= CClass.identifierStart;

        if (isAlphaNum(c) || c == '_')
            cclassTable[c] |= CClass.identifierChar;

        if (c == ' ' ||
            c == '\t' ||
            c == '\n' ||
            c == '\v' ||
            c == '\f' ||
            c == '\r' ||
            c == '$' ||
            c == '(' ||
            c == ')' ||
            c == ',' ||
            c == ';' ||
            c == '?' ||
            c == '[' ||
            c == ']' ||
            c == '{' ||
            c == '}' ||
            c == '~')
        {
            cclassTable[c] |= CClass.separator;
        }

        if (c == '*' ||
            c == '+' ||
            c == '-' ||
            c == '.' ||
            c == '/' ||
            c == ':' ||
            c == '<' ||
            c == '=' ||
            c == '>' ||
            c == '^' ||
            c == '|')
        {
            cclassTable[c] |= CClass.multiTok;
        }
    }
}

bool isIdentifierStart(uchar c) pure nothrow
{
    return cclassTable[c] & CClass.identifierStart;
}

unittest
{
    /* Exhaustively test every char
     */
    for (uint u = 0; u < 0x100; ++u)
    {
        assert(isIdentifierStart(cast(uchar)u) == (isAlpha(u) || u == '_'));
    }
}


/*******************************************
 * Characters that make up the tail of an identifier.
 */

ubyte isIdentifierChar(uchar c) pure nothrow
{
    return cclassTable[c] & CClass.identifierChar;
}

unittest
{
    /* Exhaustively test every char
     */
    for (uint u = 0; u < 0x100; ++u)
    {
        assert((isIdentifierChar(cast(uchar)u) != 0) == (isAlphaNum(u) || u == '_'));
    }
}


/*****************************************
 * 'Break' characters unambiguously separate tokens
 */

ubyte isBreak(uchar c) pure nothrow
{
    return cclassTable[c] & CClass.separator;
}


/*************************************
 * 'MultiTok' characters can be part of multiple character tokens
 */

ubyte isMultiTok(uchar c) pure nothrow
{
    return cclassTable[c] & CClass.multiTok;
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */

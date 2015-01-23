#! /bin/sh

errors=0
warp="warp -Iinclude -I."

assert_eq() {
    if [ $1 -ne $2 ]
    then
        fail expected $2, got $1
        return 1
    fi
}

assert_equal() {
    if [ "$1" != "$2" ]
    then
        fail
        actualf=`mktemp`
        expectedf=`mktemp`
        echo "$1" > "$actualf"
        echo "$2" > "$expectedf"
        echo "--- EXPECTED"
        echo "+++ ACTUAL"
        diff -u "$expectedf" "$actualf" | tail -n +3
        return 1
    fi
}

fail() {
    if [ -n "$1" ]
    then
        echo "FAIL: $@"
    else
        echo FAIL
    fi
    errors=$((errors + 1))
}

pass() {
    echo pass
}

cd tests

printf 'comment_after_include...'
err=`$warp --stdout comment_after_include.c 2>&1 > /dev/null`
assert_equal "$err" "" && pass

printf 'dollar_macro...'
q_count=`$warp --stdout dollar_macro.S 2>&1 | egrep -c "[$]q"`
assert_eq "$q_count" 1 && pass

printf 'import...'
foo_count=`$warp --stdout import.c | fgrep -c 'int foo'`
assert_eq $foo_count 1 && pass

printf 'include_guard...'
foo_count=`$warp --stdout include_guard.c | fgrep -c 'int foo'`
assert_eq $foo_count 1 && pass

printf 'include_thrice...'
foo_count=`$warp --stdout include_thrice.c | fgrep -c 'int foo'`
assert_eq $foo_count 3 && pass

printf 'missing_include...'
err=`$warp --stdout include_nonexisting.c 2>&1 > /dev/null`
assert_equal "$err" "In file included from include/include_nonexisting.h:2,
                 from include_nonexisting.c:1:
include/include_doesnotexist.h:1: #include file 'doesnotexist.h' not found" && pass

printf 'pragma_once...'
foo_count=`$warp --stdout pragma_once.c | fgrep -c 'int foo'`
assert_eq $foo_count 1 && pass

printf 'space_after_include...'
err=`$warp --stdout space_after_include.cpp 2>&1 > /dev/null`
assert_equal "$err" "" && pass

if [ $errors -eq 0 ]
then
    echo "All tests passed"
else
    echo "$errors tests failed"
    exit 1
fi

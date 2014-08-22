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

printf 'include_guard...'
foo_count=`$warp --stdout include_guard.c | fgrep -c 'int foo'`
assert_eq $foo_count 1 && pass

printf 'include_thrice...'
foo_count=`$warp --stdout include_thrice.c | fgrep -c 'int foo'`
assert_eq $foo_count 3 && pass

printf 'pragma_once...'
foo_count=`$warp --stdout pragma_once.c | fgrep -c 'int foo'`
assert_eq $foo_count 1 && pass

if [ $errors -eq 0 ]
then
    echo "All tests passed"
else
    echo "$errors test failed"
    exit 1
fi

ROOT_DIR="$( cd "$( dirname $( dirname "${BASH_SOURCE[0]}" ) )" >/dev/null 2>&1 && pwd )"

rm $ROOT_DIR/.git/hooks/*
cp $ROOT_DIR/.githooks/* $ROOT_DIR/.git/hooks/
chmod 755 $ROOT_DIR/.git/hooks/*


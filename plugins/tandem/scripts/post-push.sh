#!/bin/sh
# The post-push hook is removed. Sessions started before its removal still call this path from their
# startup snapshot of hooks; exit quietly until they restart, then delete this file.
exit 0

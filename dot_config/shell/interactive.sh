# Keep the desktop session Chinese while making all interactive CLI locale
# categories English.
unset LC_ALL LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT
unset LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME
LANG="en_US.UTF-8"
LANGUAGE="en_US:en"

export LANG
export LANGUAGE

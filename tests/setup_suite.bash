setup_suite() {
  echo '# Installing envsubst' >&2
  apk --no-cache add gettext | sed -e 's/^/# /' >&2
}

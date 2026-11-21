set -euo pipefail
VERSION=1.1.42
output="$(java -jar myapp/target/myapp-1.1.42.jar "$VERSION")"
printf '%s\n' "$output"
grep -q 'Hello World!' <<<"$output" && echo 'CHECK1 OK (Hello World!)'
grep -qF 'My Name is Daniel Barel' <<<"$output" && echo 'CHECK2 OK (name line)'
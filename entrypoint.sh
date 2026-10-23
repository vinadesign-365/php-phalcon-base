#!/bin/sh
# Prepare one mbn-cms site in /var/www/app, then run php-fpm + nginx.
# The container exits when either process dies, so Docker restarts it.
set -eu

APP=/var/www/app
CONF="$APP/app/configs/__config_install.php"

# php-fpm runs with clear_env=yes, so the app reads its settings from __config_install.php,
# written here from the container env. A mounted config file is used when DB_NAME is not set.
# THEME_NAME set but empty is written as "" (some sites read the theme from the DB options table);
# THEME_NAME unset leaves the key out, so config.php applies its own default.
if [ -n "${DB_NAME:-}" ]; then
    php -r '
        $map = [
            "db_name" => "DB_NAME", "db_user" => "DB_USER", "db_pass" => "DB_PASS",
            "db_host" => "DB_HOST", "db_port" => "DB_PORT",
            "base_url" => "BASE_URL", "protocol" => "PROTOCOL",
            "redis_host" => "REDIS_HOST", "redis_port" => "REDIS_PORT",
        ];
        $c = ["protocol" => "https"];
        foreach ($map as $key => $env) {
            $v = getenv($env);
            if ($v !== false && $v !== "") $c[$key] = $v;
        }
        if (getenv("THEME_NAME") !== false) $c["theme_name"] = getenv("THEME_NAME");
        file_put_contents($argv[1], "<?php\n\$configInstall = " . var_export($c, true) . ";\n");
    ' "$CONF"
    chown root:www-data "$CONF"
    chmod 640 "$CONF"
elif [ ! -f "$CONF" ]; then
    echo "entrypoint: set DB_NAME/DB_USER/DB_PASS/DB_HOST/BASE_URL/THEME_NAME or mount $CONF" >&2
    exit 1
fi

# Only these paths are writable by php. Volumes come in root-owned on first mount.
# /var/lib/php/sessions is session.save_path for sites without their own session dir.
mkdir -p "$APP/web/uploads" "$APP/.session/tmp" "$APP/logs" /var/lib/php/sessions
for theme in "$APP"/web/themes/*/; do
    mkdir -p "${theme}caches/volt"
done
for dir in "$APP/web/uploads" "$APP/.session" "$APP/logs" /var/lib/php/sessions "$APP"/web/themes/*/caches; do
    find "$dir" ! -user www-data -exec chown www-data:www-data {} +
done

php-fpm --nodaemonize &
FPM_PID=$!
nginx -g 'daemon off;' &
NGINX_PID=$!

STOPPING=0
trap 'STOPPING=1; kill -TERM $FPM_PID $NGINX_PID 2>/dev/null' TERM INT
# wait -n is not in POSIX sh: poll until one of the two processes is gone.
while kill -0 $FPM_PID 2>/dev/null && kill -0 $NGINX_PID 2>/dev/null; do
    sleep 1
done
[ "$STOPPING" = 1 ] || echo "entrypoint: php-fpm or nginx stopped, exiting" >&2
kill -TERM $FPM_PID $NGINX_PID 2>/dev/null || true
wait
[ "$STOPPING" = 1 ] && exit 0
exit 1

#cloud-config
write_files:
  - path: /usr/local/bin/pgadmin-add-users.py
    permissions: '0700'
    owner: root:root
    content: |
      import sys, sqlite3, uuid, hmac as hmaclib, hashlib, base64, os, importlib.util
      sys.path.insert(0, '/usr/pgadmin4/web')
      sys.path.insert(0, '/usr/pgadmin4/venv/lib/python3.10/site-packages')
      from passlib.hash import pbkdf2_sha512

      def read_salt():
          for path in ['/usr/pgadmin4/web/config_local.py',
                       '/var/lib/pgadmin/config_local.py']:
              if not os.path.exists(path):
                  continue
              try:
                  spec = importlib.util.spec_from_file_location('_cfg', path)
                  m = importlib.util.module_from_spec(spec)
                  spec.loader.exec_module(m)
                  v = getattr(m, 'SECURITY_PASSWORD_SALT', None)
                  if v:
                      print('[add-users] SALT found in ' + path + ' len=' + str(len(v)))
                      return v
              except Exception as e:
                  print('[add-users] error reading ' + path + ': ' + str(e))
          # fallback: try base config
          try:
              import config
              v = getattr(config, 'SECURITY_PASSWORD_SALT', None)
              if v:
                  print('[add-users] SALT found in config.py len=' + str(len(v)))
                  return v
          except Exception as e:
              print('[add-users] error reading config.py: ' + str(e))
          print('[add-users] SALT not found - hashing plain password')
          return None

      def make_hash(password, salt):
          if salt:
              s = salt.encode('utf-8') if isinstance(salt, str) else salt
              p = password.encode('utf-8') if isinstance(password, str) else password
              h = hmaclib.new(s, p, digestmod=hashlib.sha512)
              password = base64.b64encode(h.digest()).decode('ascii')
          return pbkdf2_sha512.hash(password)

      DB = '/var/lib/pgadmin/pgadmin4.db'
      with open(sys.argv[1]) as f:
          lines = [l.rstrip('\n') for l in f if l.strip()]
      pairs = [(lines[i], lines[i+1]) for i in range(0, len(lines), 2)]

      salt = read_salt()

      conn = sqlite3.connect(DB)
      cur = conn.cursor()
      cur.execute("SELECT id FROM role WHERE name='Administrator'")
      row = cur.fetchone()
      admin_role_id = row[0] if row else None

      for email, password in pairs:
          cur.execute('SELECT id FROM "user" WHERE username=?', (email,))
          if cur.fetchone():
              continue
          pw_hash = make_hash(password, salt)
          uid = uuid.uuid4().hex
          cur.execute(
              'INSERT INTO "user" (email,username,password,active,confirmed_at,auth_source,fs_uniquifier,login_attempts,locked) VALUES (?,?,?,1,datetime("now"),"internal",?,0,0)',
              (email, email, pw_hash, uid)
          )
          user_id = cur.lastrowid
          if admin_role_id:
              cur.execute('INSERT INTO roles_users (user_id,role_id) VALUES (?,?)', (user_id, admin_role_id))
          print('[add-users] added ' + email)

      cur.execute('DELETE FROM "user" WHERE email="init@example.com"')
      conn.commit()
      try:
          conn.execute('PRAGMA wal_checkpoint(FULL)')
      except Exception:
          pass
      conn.close()

  - path: /usr/local/bin/pgadmin-test-db.py
    permissions: '0700'
    owner: root:root
    content: |
      import sys, sqlite3, os, stat
      DB = '/var/lib/pgadmin/pgadmin4.db'
      conn = sqlite3.connect(DB)
      tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]
      for t in ['user', 'role', 'roles_users']:
          print('[pgadmin-test] table ' + t + ': ' + ('OK' if t in tables else 'MISSING'))
      for r in conn.execute('SELECT id,email,username,auth_source,active,login_attempts,locked FROM "user"'):
          print('[pgadmin-test] user: ' + str(r))
      s = os.stat(DB)
      import pwd, grp
      print('[pgadmin-test] db_perms: ' + pwd.getpwuid(s.st_uid).pw_name + ':' + grp.getgrgid(s.st_gid).gr_name + ' ' + oct(stat.S_IMODE(s.st_mode)))
      conn.close()

  - path: /usr/local/bin/pgadmin-test-hash.py
    permissions: '0700'
    owner: root:root
    content: |
      import sys, sqlite3
      sys.path.insert(0, '/usr/pgadmin4/venv/lib/python3.10/site-packages')
      from passlib.hash import pbkdf2_sha512
      from unicodedata import normalize, is_normalized

      def normalise(p):
          return p if is_normalized('NFKD', p) else normalize('NFKD', p)

      DB = '/var/lib/pgadmin/pgadmin4.db'
      with open(sys.argv[1]) as f:
          lines = [l.rstrip('\n') for l in f if l.strip()]
      passwords = {lines[i]: lines[i+1] for i in range(0, len(lines), 2)}

      conn = sqlite3.connect(DB)
      for r in conn.execute('SELECT email, password FROM "user" WHERE email != "init@example.com"'):
          email, pw_stored = r
          test_pw = passwords.get(email, '')
          if not pw_stored or not test_pw:
              print('[pgadmin-test] hash_verify ' + email + ': SKIP')
              continue
          try:
              ok = pbkdf2_sha512.verify(normalise(test_pw), str(pw_stored))
              print('[pgadmin-test] hash_verify ' + email + ': ' + ('PASS' if ok else 'FAIL'))
          except Exception as e:
              print('[pgadmin-test] hash_verify ' + email + ': ERROR ' + str(e))
      conn.close()

  - path: /usr/pgadmin4/web/config_local.py
    permissions: '0644'
    owner: root:root
    content: |
      SECURITY_PASSWORD_SALT = 'pgadmin-fixed-salt-for-provisioning'

  - path: /usr/local/bin/pgadmin-diag-hash.py
    permissions: '0700'
    owner: root:root
    content: |
      import sys, sqlite3, hmac as hmaclib, hashlib, base64, importlib.util, os
      sys.path.insert(0, '/usr/pgadmin4/venv/lib/python3.10/site-packages')
      from passlib.hash import pbkdf2_sha512

      print('[diag] /usr/pgadmin4/web/config_local.py contents:')
      try:
          with open('/usr/pgadmin4/web/config_local.py') as f:
              print(f.read())
      except Exception as e:
          print('ERROR: ' + str(e))

      DB = '/var/lib/pgadmin/pgadmin4.db'
      conn = sqlite3.connect(DB)
      stored = conn.execute("SELECT password FROM user WHERE email='init@example.com'").fetchone()
      conn.close()
      if not stored:
          print('[diag] init@example.com not found in DB')
          sys.exit(0)
      stored = stored[0]
      print('[diag] stored hash prefix: ' + stored[:60])

      test_pw = 'Init1234!'

      ok1 = pbkdf2_sha512.verify(test_pw, stored)
      print('[diag] plain verify Init1234!: ' + ('PASS' if ok1 else 'FAIL'))

      p = '/usr/pgadmin4/web/config_local.py'

      if salt:
          h = hmaclib.new(salt.encode('utf-8'), test_pw.encode('utf-8'), digestmod=hashlib.sha512)
          peppered = base64.b64encode(h.digest()).decode('ascii')
          ok2 = pbkdf2_sha512.verify(peppered, stored)
          print('[diag] HMAC(salt,Init1234!) verify: ' + ('PASS' if ok2 else 'FAIL'))

  - path: /usr/local/bin/pgadmin-add-postgres-servers.py
    permissions: '0700'
    owner: root:root
    content: |
      import sys, sqlite3

      DB = '/var/lib/pgadmin/pgadmin4.db'
      conn = sqlite3.connect(DB)
      cur = conn.cursor()

      cols = [r[1] for r in cur.execute("PRAGMA table_info(server)").fetchall()]

      # Alles bereinigen
      cur.execute('DELETE FROM server')
      cur.execute('DELETE FROM servergroup')

      users = cur.execute("SELECT id FROM \"user\" WHERE auth_source='internal'").fetchall()

      for (user_id,) in users:
          try:
              cur.execute("INSERT INTO servergroup (user_id, name) VALUES (?, 'Servers')", (user_id,))
              group_id = cur.lastrowid

              fields = {
                  'user_id': user_id,
                  'servergroup_id': group_id,
                  'name': 'pagila (local)',
                  'host': 'localhost',
                  'port': 5432,
                  'maintenance_db': 'pagila',
                  'username': 'pagila_user',
              }
              for col, val in [('use_ssh_tunnel', 0), ('shared', 0), ('db_res', 'pagila')]:
                  if col in cols:
                      fields[col] = val

              col_names = ', '.join(fields.keys())
              placeholders = ', '.join(['?'] * len(fields))
              cur.execute(
                  'INSERT INTO server (' + col_names + ') VALUES (' + placeholders + ')',
                  list(fields.values())
              )
              print('[add-servers] registered pagila server for user_id=' + str(user_id))
          except Exception as e:
              print('[add-servers] ERROR for user_id=' + str(user_id) + ': ' + str(e))

      conn.commit()
      conn.close()

      conn.commit()
      conn.close()

      conn.commit()
      conn.close()

  - path: /tmp/pgadmin_users.txt
    permissions: '0600'
    owner: root:root
    content: |
%{ for uid, user in users ~}
      ${user.email}
      ${passwords[uid]}
%{ endfor ~}

  - path: /usr/local/bin/pgadmin-provision.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      set -uo pipefail
      LOG="[pgadmin-provision]"
      PY=/usr/pgadmin4/venv/bin/python3
      USERS_FILE=/tmp/pgadmin_users.txt

      # Apache stoppt beim VM-Boot automatisch vor cloud-init und öffnet die DB.
      # Das verhindert, dass setup-web.sh die DB schreiben kann.
      systemctl stop apache2 || true
      sleep 2

      # ── 1. DB initialisieren via setup-web.sh ─────────────────────────────────
      echo "$LOG STEP 1: setup-web.sh (DB + Apache)..."
      PGADMIN_SETUP_EMAIL='init@example.com' \
      PGADMIN_SETUP_PASSWORD='Init1234!' \
        /usr/pgadmin4/bin/setup-web.sh --yes
      echo "$LOG setup-web.sh done."

      # ── 3. Warten bis Apache/pgAdmin bereit ──────────────────────────────────
      echo "$LOG STEP 2: Waiting for pgAdmin..."
      for i in $(seq 1 60); do
        curl -sf http://localhost/pgadmin4/login > /dev/null 2>&1 && echo "$LOG pgAdmin ready." && break
        sleep 5
      done

      # ── 4. TEST: Schema nach setup-web.sh ────────────────────────────────────
      echo "$LOG STEP 3: DB schema check (before user add)..."
      $PY /usr/local/bin/pgadmin-test-db.py 2>&1

      # ── DIAGNOSE: Hash-Format und Salt ───────────────────────────────────────
      echo "$LOG DIAG: running hash diagnostics..."
      $PY /usr/local/bin/pgadmin-diag-hash.py 2>&1 || true

      # ── 5. Echte User hinzufügen ──────────────────────────────────────────────
      echo "$LOG STEP 4: Adding real users..."
      systemctl stop apache2
      $PY /usr/local/bin/pgadmin-add-users.py $USERS_FILE
      echo "$LOG add-users done."

      # ── 6. Rechte setzen ─────────────────────────────────────────────────────
      echo "$LOG STEP 5: Setting permissions..."
      chown -R www-data:www-data /var/lib/pgadmin/
      chmod 660 /var/lib/pgadmin/pgadmin4.db \
                /var/lib/pgadmin/pgadmin4.db-wal \
                /var/lib/pgadmin/pgadmin4.db-shm 2>/dev/null || true

      # ── 6b. PostgreSQL starten und Server-Eintrag für alle User anlegen ──────
      echo "$LOG STEP 5b: Starting PostgreSQL..."
      systemctl start postgresql
      systemctl enable postgresql
      echo "$LOG STEP 5b: Registering pagila server in pgAdmin for all users..."
      $PY /usr/local/bin/pgadmin-add-postgres-servers.py 2>&1

      # ── 7. TEST: DB-Inhalt und Hashes nach User-Add ───────────────────────────
      echo "$LOG STEP 6: DB user + hash check (after user add)..."
      $PY /usr/local/bin/pgadmin-test-db.py 2>&1
      $PY /usr/local/bin/pgadmin-test-hash.py $USERS_FILE 2>&1

      # ── 8. Apache neu starten (wichtig: damit pgAdmin die neue DB liest) ──────
      echo "$LOG STEP 7: Restarting Apache to pick up new users..."
      systemctl restart apache2
      for i in $(seq 1 60); do
        curl -sf http://localhost/pgadmin4/login > /dev/null 2>&1 && echo "$LOG pgAdmin ready after restart." && break
        sleep 5
      done

      # ── 9. TEST: HTTP-Status nach Neustart ────────────────────────────────────
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost/pgadmin4/login)
      echo "[pgadmin-test] HTTP status after restart: $HTTP_CODE (expected 200)"

      echo "$LOG All steps done."
      rm -f $USERS_FILE

runcmd:
  - bash /usr/local/bin/pgadmin-provision.sh

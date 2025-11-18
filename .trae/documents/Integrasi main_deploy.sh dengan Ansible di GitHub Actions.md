## Tujuan
- Integrasikan proses deploy saat ini (yang memanggil `main_deploy.sh`) ke Ansible dalam pipeline CI/CD GitHub Actions.
- Pertahankan alur rilis timestamped (`releases/TS` + symlink `current`), jalankan Composer/NPM/Artisan secara terkelola, dan tingkatkan idempotensi, keamanan, serta linting.

## Strategi Integrasi
1. Wrap-and-call (cepat): Jalankan `main_deploy.sh` dari Ansible (`ansible.builtin.script` atau `ansible.builtin.shell`) setelah menyalin artefak. Minimal perubahan, namun idempotensi rendah.
2. Port-to-roles (disarankan): Migrasikan isi `main_deploy.sh` menjadi role Ansible (`roles/kangbeef-app`) dengan task idempoten: unarchive, composer, npm build, artisan migrate/cache, permission, symlink, service restart.

## Perubahan pada Workflow
- Lokasi yang diubah: `.github/workflows/workflow.yml:269–337` (job `deploy`).
- Ganti langkah SCP + SSH dengan eksekusi `ansible-playbook`:

```yaml
jobs:
  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/dev'
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Install Ansible & deps
        run: |
          python -m pip install --upgrade pip
          pip install ansible ansible-lint community.general
      - name: Prepare SSH key
        env:
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
        run: |
          mkdir -p ~/.ssh && chmod 700 ~/.ssh
          echo "$DEPLOY_SSH_KEY" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
      - name: Build release tarball
        run: |
          git archive -o release.tar HEAD
      - name: Lint playbooks
        run: |
          ansible-lint ansible/playbooks/deploy.yml
      - name: Run Ansible deploy
        run: |
          ansible-playbook ansible/playbooks/deploy.yml \
            -i ansible/inventories/${{ github.ref_name == 'main' && 'production' || 'staging' }}/hosts \
            -e branch=${{ github.ref_name }} -e build_sha=${{ github.sha }}
      - name: Set deployment URL
        id: seturl
        run: |
          if [ "${{ github.ref_name }}" = "main" ]; then echo "url=https://kangbeef.com" >> $GITHUB_OUTPUT; else echo "url=https://staging.kangbeef.com" >> $GITHUB_OUTPUT; fi
```

## Struktur Ansible yang Diusulkan
- `ansible/inventories/{production,staging}/hosts`
- `ansible/group_vars/{production,staging}/vars.yml` (non-rahasia)
- `ansible/playbooks/deploy.yml`
- `ansible/roles/kangbeef-app/{tasks,templates,files,vars}`
- `ansible/requirements.yml` (koleksi seperti `community.general`)

## Contoh Playbook (ringkas)
```yaml
- hosts: app
  become: true
  vars:
    releases_dir: "/var/www/kangbeef/releases"
    shared_dir: "/var/www/kangbeef/shared"
    current_link: "/var/www/kangbeef/current"
    release_ts: "{{ lookup('pipe','date +%Y%m%d%H%M%S') }}"
  tasks:
    - file: path={{ releases_dir }}/{{ release_ts }} state=directory mode=0755
    - unarchive: src=release.tar dest={{ releases_dir }}/{{ release_ts }} remote_src=no
    - file: src={{ releases_dir }}/{{ release_ts }} path={{ current_link }} state=link force=yes
    - file: path={{ current_link }}/storage state=directory mode=0775
    - file: path={{ current_link }}/bootstrap/cache state=directory mode=0775
    - community.general.composer:
        command: install
        working_dir: "{{ current_link }}"
        no_dev: true
        prefer_dist: true
        optimize_autoloader: true
    - community.general.npm:
        path: "{{ current_link }}"
        production: true
    - command: php artisan key:generate --force chdir={{ current_link }}
    - command: php artisan migrate --force chdir={{ current_link }}
    - command: php artisan config:cache chdir={{ current_link }}
    - command: php artisan route:cache chdir={{ current_link }}
    - systemd: name=php-fpm state=restarted
    - systemd: name=nginx state=reloaded
```

## Praktik Terbaik
- Idempotensi: gunakan modul (unarchive, composer, npm, systemd) alih-alih `shell`.
- FQCN: gunakan nama modul lengkap (`community.general.composer`) untuk kejelasan.
- Tagging: beri `tags: [deploy, migrate, build]` agar selektif saat menjalankan.
- Check mode: aktifkan `--check` untuk dry-run di PR.
- Linting: jalankan `ansible-lint` untuk menegakkan rule kualitas.
- Variabel per lingkungan: pisahkan `group_vars` untuk staging/production.
- Health check: tambahkan task HTTP ping aplikasi pasca-deploy.

## Keamanan & Secrets
- Simpan rahasia aplikasi di Ansible Vault; password vault via `${{ secrets.ANSIBLE_VAULT_PASSWORD }}`.
- Hindari logging rahasia (`no_log: true` pada task sensitif).
- SSH key hanya dibuat sementara di runner; set permission ketat.

## Observabilitas & Ringkasan
- Tulis status deploy ke `GITHUB_STEP_SUMMARY` dan laporkan URL lingkungan seperti pada workflow saat ini.
- Registrasi output Ansible (failed/changed/ok) untuk ringkasan.

## Validasi
- Gunakan `needs: test` untuk memastikan test lulus sebelum deploy.
- Tambahkan smoke test HTTP (status 200) setelah `systemd` restart.
- Rollback sederhana: simpan N rilis, dan symlink `current` kembali ke rilis sebelumnya bila gagal.

## Catatan Lokasi Kode
- Workflow deploy yang akan disentuh: `.github/workflows/workflow.yml:269–337`.
- Script yang saat ini dirujuk (untuk opsi wrap-and-call): `scripts/main_deploy.sh`.

## Referensi (Context7)
- Ansible Lint rules: `/ansible/ansible-lint` (rules, praktik kualitas) — contoh aturan: `fqcn`, `command-instead-of-module`, `no-log-password`.
- Ansible Runner: `/ansible/ansible-runner` (menjalankan Ansible dengan isolasi proses/eksekusi, relevan jika ingin containerize eksekusi di CI).

Silakan konfirmasi opsi Strategi Integrasi (wrap-and-call atau port-to-roles). Setelah disetujui, saya akan menerapkan perubahan pada workflow dan menambahkan playbook/role sesuai struktur di atas.
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Shell utility library

This file is the part of the cmake-abe library (https://github.com/spritetong/cmake-abe),
which is licensed under the MIT license (https://opensource.org/licenses/MIT).

Copyright (C) 2022 spritetong@gmail.com.
"""

import sys
import os

__all__ = ('ShellCmd',)


class ShellCmd:
    EFAIL = 1
    ENOENT = 7
    EINVAL = 8
    EINTERRUPT = 254

    def __init__(self, namespace):
        self.options = namespace
        self.args = namespace.args

    def run__rm(self):
        def read_arg():
            if self.options.args_from_stdin:
                import shlex
                while True:
                    try:
                        line = input()
                        lexer = shlex.shlex(line, posix=True)
                        lexer.whitespace_split = True
                        for arg in lexer:
                            yield arg
                    except EOFError:
                        break
            else:
                for arg in self.args:
                    yield arg

        def onerror(func, path, _exc_info):
            import stat
            # Is the error an access error?
            if not os.access(path, os.W_OK):
                os.chmod(path, stat.S_IWUSR)
                func(path)
            else:
                raise

        status = 0
        if not self.options.recursive:
            import glob
            for pattern in read_arg():
                files = glob.glob(pattern)
                if not files and not self.options.force:
                    print('Can not find file {}'.format(
                        pattern), file=sys.stderr)
                    return self.EFAIL
                for file in files:
                    try:
                        if os.path.isfile(file) or os.path.islink(file):
                            os.remove(file)
                        elif os.path.isdir(file):
                            os.rmdir(file)
                        else:
                            # On Windows, a link like a bad <JUNCTION> can't be accessed.
                            os.remove(file)
                    except OSError:
                        status = self.EFAIL
                        if self.options.force:
                            continue
                        print('Can not remove file {}'.format(
                            file), file=sys.stderr)
                        return status
        else:
            import shutil
            import glob
            for pattern in read_arg():
                files = glob.glob(pattern)
                if not files and not self.options.force:
                    print('Can not find file {}'.format(
                        pattern), file=sys.stderr)
                    return self.EFAIL
                for file in files:
                    try:
                        if os.path.isfile(file) or os.path.islink(file):
                            os.remove(file)
                        elif os.path.isdir(file):
                            shutil.rmtree(
                                file, ignore_errors=False, onerror=onerror)
                        else:
                            # On Windows, a link like a bad <JUNCTION> can't be accessed.
                            os.remove(file)
                    except OSError:
                        status = self.EFAIL
                        if self.options.force:
                            continue
                        print('Can not remove tree {}'.format(
                            file), file=sys.stderr)
                        return status
        return status

    def run__mkdir(self):
        import time
        status = 0
        for path in self.args:
            ok = False
            for _ in range(100):
                try:
                    if not os.path.isdir(path):
                        os.makedirs(path)
                    ok = True
                except OSError as e:
                    import errno
                    if e.errno == errno.EEXIST:
                        if os.path.isdir(path):
                            ok = True
                            break
                        else:
                            time.sleep(0.001)
                            continue
                break
            if not ok:
                status = self.EFAIL
                if self.options.force:
                    continue
                print('Can not make directory {}'.format(path), file=sys.stderr)
                return status
        return status

    def run__rmdir(self):
        status = 0
        for path in self.args:
            if not self.options.remove_empty_dirs:
                try:
                    os.rmdir(path)
                except OSError:
                    status = self.EFAIL
                    if self.options.force:
                        continue
                    print('Can not remove directory {}'.format(
                        path), file=sys.stderr)
                    return status
            else:
                def remove_empty_dirs(path):
                    # Remove empty sub-directories recursively
                    for item in os.listdir(path):
                        dir = os.path.join(path, item)
                        if os.path.isdir(dir):
                            remove_empty_dirs(dir)
                            if not os.listdir(dir):
                                os.rmdir(dir)
                if os.path.isdir(path):
                    try:
                        remove_empty_dirs(path)
                        # Try to remove empty ancestor directories.
                        while path:
                            os.rmdir(path)
                            path = os.path.dirname(path)
                    except OSError:
                        pass
        return status

    def run__mv(self):
        import shutil
        import glob

        status = 0
        if len(self.args) < 2:
            print('Invalid parameter {} for mv'.format(
                self.args), file=sys.stderr)
            return self.EFAIL
        dst = self.args[-1]
        files = []
        for pattern in self.args[:-1]:
            files += glob.glob(pattern)
        if len(files) > 1 and not os.path.isdir(dst):
            print('{} is not a direcotry'.format(dst), file=sys.stderr)
            return self.EFAIL
        if not files and not self.options.force:
            print('Can not find file {}'.format(pattern), file=sys.stderr)
            return self.EFAIL
        for file in files:
            try:
                shutil.move(file, dst)
            except OSError:
                status = self.EFAIL
                if not self.options.force:
                    print('Can not move {} to {}'.format(
                        file, dst), file=sys.stderr)
                return status
        return status

    def run__cp(self):
        import shutil
        import glob

        def copy_file(src, dst):
            if os.path.islink(src) and not self.options.follow_symlinks:
                if os.path.isdir(dst):
                    dst = os.path.join(dst, os.path.basename(src))
                if os.path.lexists(dst):
                    os.unlink(dst)
                linkto = os.readlink(src)
                os.symlink(linkto, dst)
            else:
                shutil.copy2(src, dst)

        status = 0
        if len(self.args) < 1:
            print('Invalid parameter {} for cp'.format(
                self.args), file=sys.stderr)
            return self.EFAIL
        if len(self.args) == 1:
            self.args.append('.')
        dst = self.args[-1]
        files = []
        for pattern in self.args[:-1]:
            files += glob.glob(pattern)
        if len(files) > 1 and not os.path.isdir(dst):
            print('{} is not a direcotry'.format(dst), file=sys.stderr)
            return self.EFAIL
        if not files and not self.options.force:
            print('Can not find file {}'.format(pattern), file=sys.stderr)
            return self.EFAIL
        for file in files:
            try:
                if os.path.isfile(file):
                    copy_file(file, dst)
                elif self.options.recursive:
                    shutil.copytree(file, os.path.join(
                        dst, os.path.basename(file)),
                        copy_function=copy_file, dirs_exist_ok=True)
            except OSError:
                status = self.EFAIL
                if not self.options.force:
                    print('Can not copy {} to {}'.format(
                        file, dst), file=sys.stderr)
                return status
        return status

    def run__mklink(self):
        status = 0
        if len(self.args) < 2:
            print('Invalid parameter', file=sys.stderr)
            return self.EINVAL
        link = self.args[0]
        target = self.args[1]
        try:
            target = target.replace('/', os.sep).replace('\\', os.sep)
            os.symlink(
                target, link, self.options.symlinkd or os.path.isdir(target))
        except OSError:
            status = self.EFAIL
            if not self.options.force:
                print('Can not create symbolic link: {} -> {}'.format(link, target),
                      file=sys.stderr)
        return status

    def run__fix_symlink(self):
        import glob
        is_wsl = 'WSL_DISTRO_NAME' in os.environ

        def walk(pattern):
            for file in glob.glob(pattern):
                try:
                    if os.path.isdir(file):
                        walk(os.path.join(file, '*'))
                        continue
                    is_link = os.path.islink(file)
                    if is_link and is_wsl:
                        # On WSL Linux, rebuild all file links.
                        target = os.readlink(file)
                        os.unlink(file)
                        os.symlink(target, file)
                    elif not is_link and not os.path.isfile(file):
                        # On Windows, a link like a bad <JUNCTION> can't be accessed.
                        # Try to find it's target and rebuild it.
                        for target in glob.glob(os.path.splitext(file)[0] + '.*'):
                            if os.path.isfile(target) and not os.path.islink(target):
                                os.unlink(file)
                                os.symlink(os.path.basename(target), file)
                                break
                except OSError:
                    print('Can not fix the bad symbolic link {}'.format(file),
                          file=sys.stderr)
                    raise

        try:
            for pattern in self.args:
                walk(pattern)
            return 0
        except OSError:
            return self.EFAIL

    def run__cwd(self):
        print(os.getcwd().replace('\\', '/'), end='')
        return 0

    def run__mydir(self):
        path = os.path.dirname(__file__)
        if os.path.isdir(path):
            path = os.path.realpath(path)
        else:
            path = os.getcwd()
        print(path.replace('\\', '/'), end='')
        return 0

    def run__relpath(self):
        start = None if len(self.args) <= 1 else self.args[1]
        try:
            path = self.args[0]
            path = os.path.relpath(path, start)
        except (IndexError, ValueError, OSError):
            path = ''
        print(path.replace('\\', '/'), end='')
        return 0

    def run__win2wsl_path(self):
        path = ShellCmd.win2wsl_path(
            self.args[0] if self.args else os.getcwd())
        print(path, end='')
        return 0

    def run__wsl2win_path(self):
        path = ShellCmd.wsl2win_path(
            self.args[0] if self.args else os.getcwd())
        print(path, end='')
        return 0

    def run__is_wsl_win_path(self):
        path = os.path.abspath(self.args[0]) if self.args else os.getcwd()
        path = path.replace('\\', '/')
        if len(path) >= 6 and path.startswith('/mnt/') and path[5].isalpha():
            if len(path) == 6 or path[6] == '/':
                print('true', end='')
                return 0
        print('false', end='')
        return 0

    def run__touch(self):
        import glob
        status = 0
        for pattern in self.args:
            files = glob.glob(pattern)
            if not files:
                try:
                    open(pattern, 'ab').close()
                except OSError:
                    status = self.EFAIL
                    if self.options.force:
                        continue
                    print('Can not create file {}'.format(
                        pattern), file=sys.stderr)
                    return status
            for file in files:
                try:
                    os.utime(file, None)
                except OSError:
                    status = self.EFAIL
                    if self.options.force:
                        continue
                    print('Can not touch file {}'.format(file), file=sys.stderr)
                    return status
        return status

    def run__timestamp(self):
        import time
        print(time.time(), end='')
        return 0

    def run__cmpver(self):
        try:
            v1 = [int(x) for x in (self.args[0] + '.0.0.0').split('.')[:4]]
            v2 = [int(x) for x in (self.args[1] + '.0.0.0').split('.')[:4]]
            if v1 > v2:
                result = (1, '+')
            elif v1 == v2:
                result = (0, '0')
            else:
                result = (2, '-')
        except (IndexError, ValueError):
            result = (self.EINVAL, '')
            print('Invalid arguments', file=sys.stderr)
        print(result[1], end='')
        return 0 if self.options.force else result[0]

    def run__winreg(self):
        try:
            value = None
            try:
                import winreg
                root_keys = {
                    'HKEY_CLASSES_ROOT': winreg.HKEY_CLASSES_ROOT,
                    'HKEY_CURRENT_USER': winreg.HKEY_CURRENT_USER,
                    'HKEY_LOCAL_MACHINE': winreg.HKEY_LOCAL_MACHINE,
                    'HKEY_USERS': winreg.HKEY_USERS,
                    'HKEY_PERFORMANCE_DATA': winreg.HKEY_PERFORMANCE_DATA,
                    'HKEY_CURRENT_CONFIG': winreg.HKEY_CURRENT_CONFIG,
                }
                for arg in self.args:
                    keys = arg.split('\\')
                    # Read registry.
                    key = root_keys[keys[0]]
                    sub_key = '\\'.join(keys[1:-1])
                    value_name = keys[-1]
                    try:
                        with winreg.OpenKey(key, sub_key, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as rkey:
                            value = winreg.QueryValueEx(rkey, value_name)[0]
                            if value:
                                break
                    except WindowsError:
                        pass
            except ImportError:
                pass
            print(value or '', end='')
            return 0
        except (NameError, AttributeError):
            return self.EFAIL

    def run__ndk_root(self):
        ndk_root = ShellCmd.ndk_root()
        if ndk_root:
            print(ndk_root, end='')
            return 0
        return self.ENOENT

    def run__cargo_exec(self):
        import time
        import subprocess
        if len(self.args) < 1:
            print('Invalid parameter {} for cargo-exec'.format(
                self.args), file=sys.stderr)
            return self.EFAIL
        ws_dir = os.environ.get('CARGO_WORKSPACE_DIR', '.')
        cfg_file = self.args[0] if self.args[0].endswith(
            '.toml') else os.path.join(self.args[0], 'Cargo.toml')
        cargo_toml = os.path.join(ws_dir, cfg_file) if os.path.isfile(
            os.path.join(ws_dir, cfg_file)) else cfg_file
        try:
            import toml
            cargo = toml.load(cargo_toml)
        except ImportError:
            try:
                tomllib = __import__('tomllib')
                with open(cargo_toml, mode='rb') as fp:
                    cargo = tomllib.load(fp)
            except ImportError:
                print(
                    'toml is not installed. Please execute: pip install toml', file=sys.stderr)
                return self.EFAIL
        package = cargo['package']
        os.environ['CARGO_CRATE_NAME'] = package['name']
        os.environ['CARGO_PKG_NAME'] = package['name']
        os.environ['CARGO_PKG_VERSION'] = package['version']
        os.environ['CARGO_MAKE_TIMESTAMP'] = '{}'.format(time.time())
        return subprocess.call(' '.join(self.args[1:]), shell=True)

    def run__upload(self):
        import urllib.parse
        import glob

        if len(self.args) < 2:
            print(
                'Invalid parameter {} for upload'.format(self.args), file=sys.stderr)
            return self.EFAIL

        ftp_path = self.args[0]
        files = self.args[1:]

        parsed = urllib.parse.urlparse(ftp_path)
        if not parsed.hostname:
            print('No hostname'.format(self.args), file=sys.stderr)
            return self.EINVAL
        scheme = parsed.scheme
        hostname = parsed.hostname
        port = int(parsed.port) if parsed.port else 0
        url = scheme + '://' + \
            ('{}:{}'.format(hostname, port) if port else hostname)
        username = parsed.username or ''
        password = parsed.password or ''
        remote_dir = parsed.path or '/'

        ftp = None
        ssh = None
        sftp = None
        if scheme in ['ftp', 'ftps']:
            import ftplib
            ftp = ftplib.FTP()
            ftp.connect(hostname, port or 21)
            ftp.login(username, password)
            if scheme == 'ftps':
                ftp.prot_p()
            ftp.set_pasv(True)
        elif scheme == 'sftp':
            try:
                import paramiko
            except ImportError:
                print(
                    'paramiko is not installed. Please execute: pip install paramiko', file=sys.stderr)
                return self.EFAIL
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(hostname, port or 22, username, password)
            sftp = ssh.open_sftp()
        else:
            print('Unsupported protocol: {}'.format(scheme), file=sys.stderr)
            return self.EINVAL

        for item in files:
            pair = item.split('=')
            for local_path in glob.glob(pair[-1]):
                if not os.path.isdir(local_path):
                    remote_path = os.path.basename(
                        local_path) if len(pair) == 1 else pair[0]
                    if not remote_path.startswith('/'):
                        remote_path = '/'.join([remote_dir, remote_path])
                    if remote_path.endswith('/'):
                        remote_path = '/'.join([remote_path,
                                               os.path.basename(local_path)])
                    while '//' in remote_path:
                        remote_path = remote_path.replace('//', '/')

                    print('Upload "{}"'.format(local_path))
                    print('    to "{}{}" ...'.format(
                        url, remote_path), end="", flush=True)
                    if ftp is not None:
                        with open(local_path, 'rb') as fp:
                            ftp.storbinary('STOR {}'.format(remote_path), fp,
                                           32 * 1024, callback=lambda _sent: print('.', end='', flush=True))
                    elif sftp is not None:
                        sftp.put(local_path, remote_path)
                    print('')
        print('Done.', flush=True)

        if ftp is not None:
            ftp.quit()
        if sftp is not None:
            sftp.close()
        if ssh is not None:
            ssh.close()
        return 0

    @staticmethod
    def win2wsl_path(path):
        if os.path.isabs(path):
            path = os.path.abspath(path)
        path = path.replace('\\', '/')
        drive_path = path.split(':', 1)
        if len(drive_path) > 1 and len(drive_path[0]) == 1 and drive_path[0].isalpha():
            path = '/mnt/{}{}'.format(drive_path[0].lower(),
                                      drive_path[1]).rstrip('/')
        return path

    @staticmethod
    def wsl2win_path(path):
        if os.path.isabs(path):
            path = os.path.abspath(path)
        path = path.replace('\\', '/')
        if len(path) >= 6 and path.startswith('/mnt/') and path[5].isalpha():
            if len(path) == 6:
                path = path[5].upper() + ':/'
            elif path[6] == '/':
                path = '{}:{}'.format(path[5].upper(), path[6:])
        return path

    @staticmethod
    def ndk_root(check_env=False):
        if check_env:
            ndk_root = os.environ.get('ANDROID_NDK_ROOT', '')
            if ndk_root:
                os.environ['ANDROID_NDK_HOME'] = ndk_root
                return ndk_root

        sdk_dir = ''
        if 'ANDROID_HOME' in os.environ:
            sdk_dir = os.path.join(os.environ['ANDROID_HOME'], 'ndk')
        elif sys.platform != 'win32':
            for dir in ('/opt/ndk', '/opt/android/ndk', '/opt/android/sdk/ndk',):
                if os.path.isdir(dir):
                    sdk_dir = dir
                    break
        if not sdk_dir:
            print('The environment variable `ANDROID_HOME` is not set.',
                  file=sys.stderr)
            return ''

        try:
            import re
            pattern1 = re.compile(r'^(\d+)\.(\d+)\.(\d+)(?:\.\w+)?$')
            pattern2 = re.compile(r'^android-ndk-r(\d+)([a-z]+)$')
            ndk_dirs = []
            for name in os.listdir(sdk_dir):
                if not os.path.isfile(os.path.join(sdk_dir, name, 'build', 'cmake', 'android.toolchain.cmake')):
                    continue
                group = pattern1.match(name)
                if group:
                    ndk_dirs.append(
                        (name, [int(group[1]), int(group[2]), int(group[3])]))
                    continue
                group = pattern2.match(name)
                if group:
                    ndk_dirs.append((
                        name, [int(group[1]),
                               int(''.join(chr(ord(x) + ord('0') - ord('a'))
                                           for x in group[2])),
                               0]
                    ))
                    continue
            if ndk_dirs:
                (dir, _) = sorted(
                    ndk_dirs, key=lambda x: x[1], reverse=True)[0]
                ndk_root = os.path.join(sdk_dir, dir).replace('\\', '/')
                if check_env:
                    os.environ['ANDROID_NDK_ROOT'] = ndk_root
                    os.environ['ANDROID_NDK_HOME'] = ndk_root
                return ndk_root
        except OSError:
            pass
        return ''

    @staticmethod
    def main(args=None):
        args = args or sys.argv[1:]
        try:
            from argparse import ArgumentParser, RawTextHelpFormatter
            parser = ArgumentParser(formatter_class=RawTextHelpFormatter)
            parser.add_argument('-D', '--symlinkd',
                                action='store_true', default=False, dest='symlinkd',
                                help='creates a directory symbolic link')
            parser.add_argument('-e', '--empty-dirs',
                                action='store_true', default=False, dest='remove_empty_dirs',
                                help='remove all empty directories')
            parser.add_argument('-f', '--force',
                                action='store_true', default=False, dest='force',
                                help='ignore errors, never prompt')
            parser.add_argument('--list',
                                action='store_true', default=False, dest='list_cmds',
                                help='list all commands')
            parser.add_argument('-P', '--no-dereference',
                                action='store_false', default=True, dest='follow_symlinks',
                                help='always follow symbolic links in SOURCE')
            parser.add_argument('-p', '--parents',
                                action='store_true', default=True, dest='parents',
                                help='if existing, make parent directories as needed')
            parser.add_argument('-r', '-R', '--recursive',
                                action='store_true', default=False, dest='recursive',
                                help='copy/remove directories and their contents recursively')
            parser.add_argument('--args-from-stdin', '--stdin',
                                action='store_true', default=False, dest='args_from_stdin',
                                help='read arguments from stdin')
            parser.add_argument('command', nargs='?', default='')
            parser.add_argument('args', nargs='*', default=[])
            namespace = parser.parse_intermixed_args(args)

            if namespace.list_cmds:
                for name in dir(ShellCmd(namespace)):
                    if name.startswith('run__'):
                        print(name[5:])
                return 0

            try:
                return getattr(ShellCmd(namespace),
                               'run__' + namespace.command.replace('-', '_'))()
            except AttributeError:
                if not namespace.command:
                    print('Missing command', file=sys.stderr)
                else:
                    print('Unrecognized command "{}"'.format(
                        namespace.command), file=sys.stderr)
            return ShellCmd.EINVAL

        except KeyboardInterrupt:
            print('^C', file=sys.stderr)
            return ShellCmd.EINTERRUPT

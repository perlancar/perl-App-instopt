package App::instopt;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

use App::swcat ();
use File::chdir;
use Perinci::Object;
use PerlX::Maybe;

use vars '%Config';
our %SPEC;

our %args_common = (
    download_dir => {
        schema => 'dirname*',
        tags => ['common'],
    },
    install_dir => {
        schema => 'dirname*',
        tags => ['common'],
    },
    program_dir => {
        schema => 'dirname*',
        tags => ['common'],
    },
);

our %argopt_arch = (
    arch => {
        schema => ['software::arch*'],
    },
);

our %argopt_detail = (
    detail => {
        schema => ['true*'],
        cmdline_aliases => {l=>{}},
    },
);

sub _set_args_default {
    my $args = shift;
    if (!$args->{arch}) {
        $args->{arch} = App::swcat::_detect_arch();
    }
    if (!$args->{download_dir}) {
        require PERLANCAR::File::HomeDir;
        $args->{download_dir} = PERLANCAR::File::HomeDir::get_my_home_dir() .
            '/software';
    }
    if (!$args->{install_dir}) {
        $args->{install_dir} = "/opt";
    }
    if (!$args->{program_dir}) {
        $args->{program_dir} = "/usr/local/bin";
    }
}

my $_ua;
sub _ua {
    unless ($_ua) {
        require LWP::UserAgent;
        $_ua = LWP::UserAgent->new;
    }
    $_ua;
}

# resolve redirects
sub _real_url {
    require HTTP::Request;

    my $url = shift;

    my $ua = _ua();
    while (1) {
        my $res = $ua->simple_request(HTTP::Request->new(HEAD => $url));
        if ($res->code =~ /^3/) {
            if ($res->header("Location")) {
                $url = $res->header("Location");
                next;
            } else {
                die "URL '$url' redirects without Location";
            }
        } elsif ($res->code !~ /^2/) {
            die "Can't HEAD URL '$url': ".$res->code." - ".$res->message;
        } else {
            return $url;
        }
    }
}

sub _init {
    my ($args) = @_;

    unless ($App::instopt::state) {
        _set_args_default($args);
        my $state = {
        };
        $App::instopt::state = $state;
    }
    $App::instopt::state;
}

# if $dir has a single entry inside it, which is another dir ($wrapper), move
# the content of entries inside $wrapper to inside $dir directly.
sub _unwrap {
    my $dir = shift;

    opendir my $dh, $dir or die "Can't read dir '$dir': $!";
    my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;

    return unless @entries == 1 && (-d "$dir/$entries[0]");

    my $rand = sprintf("%08d", rand()*100_000_000);
    rename "$dir/$entries[0]", "$dir/$entries[0].$rand";

    opendir my $dh2, "$dir/$entries[0].$rand" or die "Can't read dir '$dir/$entries[0].$rand': $!";
    my @subentries = grep { $_ ne '.' && $_ ne '..' } readdir $dh2;
    closedir $dh2;

    for (@subentries) {
        rename "$dir/$entries[0].$rand/$_", "$dir/$_" or die "Can't move $dir/$entries[0].$rand/$_ to $dir/$_: $!";
    }
    rmdir "$dir/$entries[0].$rand" or die "Can't rmdir $dir/$entries[0].$rand: $!";
}

$SPEC{list_installed} = {
    v => 1.1,
    summary => 'List all installed software',
    args => {
        %args_common,
        %argopt_detail,
    },
};
sub list_installed {
    my %args = @_;
    my $state = _init(\%args);

    my $res = App::swcat::list();
    return [500, "Can't list known software: $res->[0] - $res->[1]"] if $res->[0] != 200;
    my $known = $res->[2];

    my @rows;
    {
        local $CWD = $args{install_dir};
        for my $e (glob "*") {
            next unless -l $e;
            next unless grep { $e eq $_ } @$known;
            my $v = readlink($e);
            next unless $v =~ s/\A\Q$e\E-//;

            push @rows, {
                software => $e,
                version => $v,
            };
        }
    }

    unless ($args{detail}) {
        @rows = map { $_->{software} } @rows;
    }

    [200, "OK", \@rows];
}

$SPEC{list_downloaded} = {
    v => 1.1,
    summary => 'List all downloaded software',
    args => {
        %args_common,
        %App::swcat::arg0_software,
        detail => {
            schema => ['bool*', is=>1],
            cmdline_aliases => {l=>{}},
        },
    },
};
sub list_downloaded {
    [501, "Not yet implemented"];
}

$SPEC{download} = {
    v => 1.1,
    summary => 'Download latest version of software',
    args => {
        %args_common,
        %App::swcat::arg0_software,
        %argopt_arch,
    },
};
sub download {
    require File::Path;
    require URI::Escape;

    my %args = @_;
    my $state = _init(\%args);

    my $mod = App::swcat::_load_swcat_mod($args{software});
    my $res;

    $res = App::swcat::latest_version(%args);
    return $res if $res->[0] != 200;
    my $v = $res->[2];

    $res = $mod->get_download_url(
        arch => $args{arch},
    );
    return $res if $res->[0] != 200;
    my @urls = ref($res->[2]) eq 'ARRAY' ? @{$res->[2]} : ($res->[2]);

    my $target_dir = join(
        "",
        $args{download_dir},
        "/", substr($args{software}, 0, 1),
        "/", $args{software},
        "/", $v,
        "/", $args{arch},
    );
    File::Path::make_path($target_dir);

    my $ua = _ua();
    my @files;
    for my $url0 (@urls) {
        my $url = _real_url($url0);
        my ($filename) = $url =~ m!.+/(.+)!;
        $filename = URI::Escape::uri_unescape($filename);
        my $target_path = "$target_dir/$filename";
        push @files, $target_path;
        log_info "Downloading %s to %s ...", $url, $target_path;
        my $lwpres = $ua->mirror($url, $target_path);
        unless ($lwpres->is_success || $lwpres->code =~ /^304/) {
            die "Can't download $url to $target_path: " .
                $lwpres->code." - ".$lwpres->message;
        }
    }
    [200, "OK", undef, {
        'func.version' => $v,
        'func.files' => \@files,
    }];
}

$SPEC{update} = {
    v => 1.1,
    summary => 'Update a software to the latest version',
    args => {
        %args_common,
        %App::swcat::arg0_software,
        # XXX --no-download option
    },
};
sub update {
    require Archive::Any;
    require File::MoreUtil;
    require File::Path;
    require Filename::Archive;

    my %args = @_;
    my $state = _init(\%args);

    my $mod = App::swcat::_load_swcat_mod($args{software});

  UPDATE: {
        log_info "Updating software %s ...", $args{software};

        my $res = download(%args);
        return $res if $res->[0] != 200;

        my ($filepath, $filename);
        if (@{ $res->[3]{'func.files'} } != 1) {
            return [412, "Currently cannot handle software that has multiple downloaded files"];
        }
        $filepath = $filename = $res->[3]{'func.files'}[0];
        $filename =~ s!.+/!!;

        my $cafres = Filename::Archive::check_archive_filename(
            filename => $filename);
        unless ($cafres) {
            return [412, "Currently cannot handle software that has downloaded file that is not an archive"];
        }

        my $target_name = join(
            "",
            $args{software}, "-", $res->[3]{'func.version'},
        );
        my $target_dir = join(
            "",
            $args{install_dir},
            "/", $target_name,
        );

      EXTRACT: {
            if (-d $target_dir) {
                log_debug "Target dir '$target_dir' already exists, skipping extract";
                last EXTRACT;
            }
            log_trace "Creating %s ...", $target_dir;
            File::Path::make_path($target_dir);

            log_trace "Extracting %s to %s ...", $filepath, $target_dir;
            my $ar = Archive::Any->new($filepath);
            $ar->extract($target_dir);

            _unwrap($target_dir);
        } # EXTRACT

      SYMLINK_DIR: {
            local $CWD = $args{install_dir};
            log_trace "Creating/updating directory symlink to latest version ...";
            if (File::MoreUtil::file_exists($args{software})) {
                unlink $args{software} or die "Can't unlink $args{install_dir}/$args{software}: $!";
            }
            symlink $target_name, $args{software} or die "Can't symlink $args{software} -> $target_name: $!";
        }

      SYMLINK_PROGRAMS: {
            local $CWD = $args{program_dir};
            log_trace "Creating/updating program symlinks ...";
            my $res = $mod->get_programs;
            for my $e (@{ $res->[2] }) {
                if ((-l $e->{name}) || !File::MoreUtil::file_exists($e->{name})) {
                    unlink $e->{name};
                    my $target = "$args{install_dir}/$args{software}$e->{path}/$e->{name}";
                    $target =~ s!//!/!g;
                    log_trace "Creating symlink $args{program_dir}/$e->{name} -> $target ...";
                    symlink $target, $e->{name} or die "Can't symlink $e->{name} -> $target: $!";
                } else {
                    log_warn "%s/%s is not a symlink, skipping", $args{program_dir}, $e->{name};
                    next;
                }
            }
        }

    } # UPDATE

    [200, "OK"];
}

$SPEC{update_all} = {
    v => 1.1,
    summary => 'Update all installed software',
    args => {
        %args_common,
    },
};
sub update_all {
    my %args = @_;
    my $state = _init(\%args);

    my $res = list_installed(%args);
    return $res unless $res->[0] == 200;

    my $envresmulti = envresmulti();
    for my $sw (@{ $res->[2] }) {
        $res = update(%args, software=>$sw);
        $envresmulti->add_result($res->[0], $res->[1], {item_id=>$sw});
    }

    $envresmulti->as_struct;
}

1;
# ABSTRACT: Download and install software

=head1 SYNOPSIS

See L<instopt> script.

=cut

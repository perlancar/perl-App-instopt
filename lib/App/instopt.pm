package App::instopt;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

use App::swcat ();
use PerlX::Maybe;

use vars '%Config';
our %SPEC;

our %args_common = (
    archive_dir => {
        schema => 'dirname*',
        tags => ['common'],
    },
    arch => {
        schema => 'software::arch*',
        tags => ['common'],
    },
);

our %arg_arch = (
    arch => {
        schema => ['software::arch*'],
    },
);

sub _load_swcat_mod {
    my $name = shift;

    (my $mod = "Software::Catalog::SW::$name") =~ s/-/::/g;
    (my $modpm = "$mod.pm") =~ s!::!/!g;
    require $modpm;
    $mod;
}

sub _set_args_default {
    my $args = shift;
    if (!$args->{arch}) {
        $args->{arch} = App::swcat::_detect_arch();
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

$SPEC{list_installed} = {
    v => 1.1,
    summary => 'List all installed software',
    args => {
        %args_common,
    },
};
sub list_installed {
    [501, "Not yet implemented"];
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
    },
};
sub download {
    my %args = @_;
    my $state = _init(\%args);

    return [501, "Not yet implemented"];
    my $mod = _load_swcat_mod($args{software});
    $mod->get_download_url(
        maybe arch => $args{arch},
    );
}

$SPEC{update} = {
    v => 1.1,
    summary => 'Update a software to latest version',
    args => {
        %args_common,
        %App::swcat::arg0_software,
    },
};
sub update {
    my %args = @_;
    my $state = _init(\%args);

    return [501, "Not yet implemented"];
    my $mod = _load_swcat_mod($args{software});
    $mod->get_download_url(
        maybe arch => $args{arch},
    );
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

    return [501, "Not yet implemented"];
}

1;
# ABSTRACT: Download and install software

=head1 SYNOPSIS

See L<instopt> script.

=cut

package App::ClusterSSH::Host;

use strict;
use warnings;

use version;
our $VERSION = version->new('0.03');

use Carp;
use Net::hostent;

use base qw/ App::ClusterSSH::Base /;

our %ssh_hostname_for;
our %ssh_configs_read;

sub new {
    my ( $class, %args ) = @_;

    if ( !$args{hostname} ) {
        croak(
            App::ClusterSSH::Exception->throw(
                error => $class->loc('hostname is undefined')
            )
        );
    }

    # remove any keys undef values - must be a better way...
    foreach my $remove (qw/ port username geometry /) {
        if ( !$args{$remove} && grep {/^$remove$/} keys(%args) ) {
            delete( $args{$remove} );
        }
    }

    my $self
        = $class->SUPER::new( ssh_config => "$ENV{HOME}/.ssh/config", %args );

    # load in ssh hostname for later use
    if ( !%ssh_hostname_for || !$ssh_configs_read{ $self->{ssh_config} } ) {
        $self->read_ssh_file( $self->{ssh_config} );

        $self->debug( 5, 'Have the following ssh hostnames' );
        $self->debug( 5, '  "', $_, '"' )
            foreach ( sort keys %ssh_hostname_for );
    }

    return $self;
}

sub read_ssh_file($$) {
    my ($self)     = shift;
    my ($filename) = glob(shift);
    $self->debug( 3, 'Reading SSH file: ', $filename );

    $ssh_configs_read{$filename} = 1;

    if ( open( my $ssh_config_fh, '<', $filename ) ) {
        while ( my $line = <$ssh_config_fh> ) {
            chomp $line;

            if ( $line =~ /^\s*include\s+(.+)/i ) {
                $self->read_ssh_file($1);
                next;
            }

            next unless ( $line =~ m/^\s*host\s+(.*)/i );

            # account for multiple declarations of hosts
            $ssh_hostname_for{$_} = 1 foreach ( split( /\s+/, $1 ) );
        }
        close($ssh_config_fh);
    }
    else {
        $self->debug( 3, 'Unable to read ', $filename, ': ', $!, $/ );
    }
}

sub get_hostname {
    my ($self) = @_;
    return $self->{hostname};
}

sub get_username {
    my ($self) = @_;
    return $self->{username} || q{};
}

sub get_type {
    my ($self) = @_;
    if ( $self->check_ssh_hostname ) {
        return 'ssh_alias';
    }
    return $self->{type} || q{};
}

sub get_geometry {
    my ($self) = @_;
    return $self->{geometry} || q{};
}

sub set_username {
    my ( $self, $new_username ) = @_;
    $self->{username} = $new_username;
    return $self;
}

sub get_port {
    my ($self) = @_;
    return $self->{port} || q{};
}

sub set_port {
    my ( $self, $new_port ) = @_;
    $self->{port} = $new_port;
    return $self;
}

sub set_type {
    my ( $self, $type ) = @_;
    $self->{type} = $type;
    return $self;
}

sub set_geometry {
    my ( $self, $geometry ) = @_;
    $self->{geometry} = $geometry;
    return $self;
}

sub get_master {
    my ($self) = @_;
    return $self->{master} || q{};
}

sub set_master {
    my ( $self, $new_master ) = @_;
    $self->{master} = $new_master;
    return $self;
}

sub get_realname {
    my ($self) = @_;

    if ( !$self->{realname} ) {
        if ( $self->get_type eq 'ssh_alias' ) {
            $self->{realname} = $self->{hostname};
        }
        else {
            my $gethost_obj = gethostbyname( $self->{hostname} );

            $self->{realname}
                = defined($gethost_obj)
                ? $gethost_obj->name()
                : $self->{hostname};
        }
    }
    return $self->{realname};
}

sub parse_host_string {
    my ( $self, $host_string ) = @_;
    my $parse_string = $host_string;

    $self->debug( 5, $self->loc( 'host_string=" [_1] "', $host_string ), );

    # check for bracketed IPv6 addresses
    if ($host_string =~ m{
            \A 
            (?:(.*?)@)?               # username@ (optional)
            \[([\w:]*)\]              # [<sequence of chars>]
            (?::(\d+))?               # :port     (optional)
            (?:=(\d+\D\d+\D\d+\D\d))? # =geometry (optional)
            \z
        }xms
        )
    {
        $self->debug(
            5,
            $self->loc(
                'bracketed IPv6: u=[_1] h=[_2] p=[_3] g=[_4]',
                $1, $2, $3, $4
            ),
        );
        return __PACKAGE__->new(
            parse_string => $parse_string,
            username     => $1,
            hostname     => $2,
            port         => $3,
            geometry     => $4,
            type         => 'ipv6',
        );
    }

    # check for standard IPv4 host.domain/IP address
    if ($host_string =~ m{
            \A 
            (?:(.*?)@)?               # username@ (optional)
            ([\w\.-]*)                # hostname[.domain[.domain] | 123.123.123.123
            (?::(\d+))?               # :port     (optional)
            (?:=(\d+\D\d+\D\d+\D\d+))? # =geometry (optional)
            \z
        }xms
        )
    {
        $self->debug(
            5,
            $self->loc(
                'std IPv4: u=[_1] h=[_2] p=[_3] g=[_4]',
                $1, $2, $3, $4
            ),
        );
        return __PACKAGE__->new(
            parse_string => $parse_string,
            username     => $1,
            hostname     => $2,
            port         => $3,
            geometry     => $4,
            type         => 'ipv4',
        );
    }

    # Check for unbracketed IPv6 addresses as best we can...
    my $username = q{};
    my $geometry = q{};
    my $port     = q{};

    # first, see if there is a username to grab
    if ( $host_string =~ s/\A(?:(.*?)@)// ) {

        # catch where @ is in host_string but no text before it
        $username = $1;
    }

    # check for any geometry settings
    if ( $host_string =~ s/(?:=(.*?)$)// ) {
        $geometry = $1;
    }

    # Check for a '/nnnn' port definition
    if ( $host_string =~ s!(?:/(\d+)$)!! ) {
        $port = $1;
    }

    # use number of colons as a possible indicator
    my $colon_count = $host_string =~ tr/://;

    # if there are 7 colons assume its a full IPv6 address
    # if its 8 then assumed full IPv6 address with a port
    # also catch localhost address here
    if ( $colon_count == 7 || $colon_count == 8 || $host_string eq '::1' ) {
        if ( $colon_count == 8 ) {
            $host_string =~ s/(?::(\d+?))$//;
            $port = $1;
        }
        $self->debug(
            5,
            $self->loc(
                'IPv6: u=[_1] h=[_2] p=[_3] g=[_4]',
                $username, $host_string, $port, $geometry,
            ),
        );
        return __PACKAGE__->new(
            parse_string => $parse_string,
            username     => $username,
            hostname     => $host_string,
            port         => $port,
            geometry     => $geometry,
            type         => 'ipv6',
        );
    }
    if (   $colon_count > 1
        && $colon_count < 8 )
    {
        warn 'Ambiguous host string: "', $host_string, '"',   $/;
        warn 'Assuming you meant "[',    $host_string, ']"?', $/;

        $self->debug(
            5,
            $self->loc(
                'Ambiguous IPv6 u=[_1] h=[_2] p=[_3] g=[_4]',
                $username, $host_string, $port, $geometry,
            )
        );

        return __PACKAGE__->new(
            parse_string => $parse_string,
            username     => $username,
            hostname     => $host_string,
            port         => $port,
            geometry     => $geometry,
            type         => 'ipv6',
        );
    }

    # if we got this far, we didnt parse the host_string properly
    croak(
        App::ClusterSSH::Exception->throw(
            error => $self->loc(
                'Unable to parse hostname from "[_1]"', $host_string
            )
        )
    );
}

sub check_ssh_hostname {
    my ( $self, ) = @_;

    $self->debug( 4, 'Checking ssh hosts for hostname ',
        $self->get_hostname );

    if ( $ssh_hostname_for{ $self->get_hostname } ) {
        $self->debug( 5, 'Found' );
        return 1;
    }
    else {
        $self->debug( 5, 'Not found' );
        return 0;
    }
}

use overload (
    q{""} => sub {
        my ($self) = @_;
        return $self->{hostname};
    },
    fallback => 1,
);

1;

=pod

=head1 NAME

ClusterSSH::Host - Object representing a host.

=head1 SYNOPSIS

    use ClusterSSH::Host;

    my $host = ClusterSSH::Host->new({
        hostname => 'hostname',
    });
    my $host = ClusterSSH::Host->parse_host_string('username@hostname:1234');

=head1 DESCRIPTION

Object representing a host.  Include details to contact the host such as
hostname/ipaddress, username and port.

=head1 METHODS

=over 4

=item $host=ClusterSSH::Host->new ({ hostname => 'hostname' })

Create a new host object.  'hostname' is a required arg, 'username' and 
'port' are optional.  Raises exception if an error occurs.

=item $host->get_hostname

=item $host->get_username

=item $host->get_port

=item $host->get_master

=item $host->get_geometry

=item $host->get_type

Return specific details about the host

=item $host->set_username

=item $host->set_port

=item $host->set_master

=item $host->set_geometry

=item $host->set_type

Set specific details about the host after its been created.

=item get_realname

If the server name provided is not an IP address (either IPv4 or IPv6) 
attempt to resolve it and retun the discovered names.

=item get_givenname

Alias to get_hostname, for use when C< get_realname > might return something
different

=item parse_host_string

Given a host string, returns a host object.  Parses hosts such as

=item check_ssh_hostname

Check the objects hostname to see whether or not it may be configured within 
the users F< $HOME/.ssh/config > configuration file

=item read_ssh_file

Method to ease reading in ssh configuration files.  Used for grabbing
hostnames for validation when used in clusters

=over 4

=item host

=item 192.168.0.1

=item user@host

=item user@192.168.0.1

=item host:port

=item [1234:1234:1234::4567]:port

=item 1234:1234:1234::4567

=back

and so on.  Cope with IPv4 and IPv6 addresses - raises a warning if the
IPv6 address is ambiguous (i.e. in the last example, is the 4567 part of
the IPv6 address or a port definition?) and assumes it is part of address.
Use brackets to avoid seeing warning.

=back

=head1 AUTHOR

Duncan Ferguson, C<< <duncan_j_ferguson at yahoo.co.uk> >>

=head1 LICENSE AND COPYRIGHT

Copyright 1999-2018 Duncan Ferguson.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;

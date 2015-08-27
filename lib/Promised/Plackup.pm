package Promised::Plackup;
use strict;
use warnings;
our $VERSION = '3.0';
use AnyEvent;
use Promised::Command;
use Promised::Command::Signals;

sub new ($) {
  return bless {options => {}}, $_[0];
} # new

sub stdin ($;$) {
  $_[0]->{stdin} = $_[1] if @_ > 1;
  return $_[0]->{stdin};
} # stdin

sub stdout ($;$) {
  $_[0]->{stdout} = $_[1] if @_ > 1;
  return $_[0]->{stdout};
} # stdout

sub stderr ($;$) {
  $_[0]->{stderr} = $_[1] if @_ > 1;
  return $_[0]->{stderr};
} # stderr

sub plackup ($;$) {
  if (@_ > 1) {
    $_[0]->{plackup} = $_[1];
  }
  return $_[0]->{plackup};
} # plackup

sub set_option ($$$) {
  if (defined $_[2]) {
    $_[0]->{options}->{$_[1]} = [$_[2]];
  } else {
    delete $_[0]->{options}->{$_[1]};
  }
} # set_option

sub add_option ($$$) {
  push @{$_[0]->{options}->{$_[1]} ||= []}, $_[2];
} # add_option

sub set_app_code ($$) {
  $_[0]->set_option ('-e' => $_[1]);
} # set_app_code

sub set_server ($$) {
  $_[0]->set_option ('--server' => $_[1]);
} # set_server

sub envs ($) {
  return $_[0]->{envs} ||= {};
} # envs

sub start_timeout ($;$) {
  if (@_ > 1) {
    $_[0]->{start_timeout} = $_[1];
  }
  return $_[0]->{start_timeout} || 5;
} # start_timeout

{
  use Socket;
  sub _can_listen ($) {
    my $port = $_[0] or return 0;
    my $proto = getprotobyname ('tcp');
    socket (my $server, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
    setsockopt ($server, SOL_SOCKET, SO_REUSEADDR, pack ("l", 1))
        or die "setsockopt: $!";
    bind ($server, sockaddr_in($port, INADDR_ANY)) or return 0;
    listen ($server, SOMAXCONN) or return 0;
    close ($server);
    return 1;
  } # _can_listen

  sub _find_port () {
    my $used = {};
    for (1..10000) {
      my $port = int rand (5000 - 1024); # ephemeral ports
      next if $used->{$port};
      return $port if _can_listen $port;
      $used->{$port}++;
    }
    die "Listenable port not found";
  } # _find_port
}

sub _cmd ($) {
  my $self = $_[0];
  return $self->{cmd} ||= do {
    my @cmd;
    my $plackup = $self->plackup;
    if (defined $plackup) {
      push @cmd, $plackup;
    } else {
      push @cmd, 'plackup';
    }
    unless (defined $self->{options}->{'--port'}->[0]) {
      $self->{options}->{'--host'} = ['127.0.0.1']
          unless defined $self->{options}->{'--host'}->[0];
      $self->{options}->{'--port'} = [_find_port];
    }
    for my $option (sort { $a cmp $b } keys %{$self->{options}}) {
      for my $value (@{$self->{options}->{$option} or []}) {
        push @cmd, $option => $value;
      }
    }
    my $cmd = Promised::Command->new (\@cmd);
    %{$cmd->envs} = %{$self->envs};
    $cmd->stdin ($self->stdin);
    $cmd->stdout ($self->stdout);
    $cmd->stderr ($self->stderr);
    my $stop_code = sub {
      return $self->stop;
    };
    $self->{signal}->{$_} = Promised::Command::Signals->add_handler
        ($_ => $stop_code) for qw(INT TERM QUIT);
    $cmd->signal_before_destruction ($self->_stop_signal);
    $cmd;
  };
} # _cmd

sub get_port ($) {
  my $port = $_[0]->{options}->{'--port'}->[0];
  return defined $port ? $port : die "|run| not yet invoked";
} # get_port

sub get_hostname ($) {
  my $self = $_[0];
  my $hostname = $self->{options}->{'--host'}->[0];
  $hostname = '127.0.0.1' unless defined $hostname;
  return $hostname
} # get_hostname

sub get_host ($) { # XXX percent encode?
  return $_[0]->get_hostname . ':' . $_[0]->get_port;
} # get_host

{
  use AnyEvent::Socket;
  my $Interval = 0.5;
  sub _wait_server ($$$$) {
    my ($hostname, $port, $timeout, $cmd) = @_;
    my ($ok, $ng);
    my $p = Promise->new (sub { ($ok, $ng) = @_ });
    my $try_count = 1;
    my $try; $try = sub {
      tcp_connect $hostname, $port, sub {
        if (@_) {
          my $fh = $_[0];
          #my $io; $io = AE::io $fh, 1, sub {
            #syswrite $fh, "HEAD / HTTP/1.0\x0D\x0A\x0D\x0A";
            close $fh;
            $ok->();
            undef $try;
            #undef $io;
          #};
        } else {
          if ($try_count++ > $timeout / $Interval) {
            $ng->("Server does not start in $timeout s");
            undef $try;
          } elsif (not $cmd->running) {
            $ng->("Server failed to start");
            undef $try;
          } else {
            my $timer; $timer = AE::timer $Interval, 0, sub {
              $try->();
              undef $timer;
            };
          }
        }
      };
    }; # $try
    $try->();
    return $p;
  } # _wait_server
}

sub start ($) {
  my $self = $_[0];
  my $cmd = $self->_cmd;
  $self->{start_pid} = $$;
  return $cmd->run->then (sub {
    if ($cmd->running) {
      return (_wait_server $self->get_hostname, $self->get_port, $self->start_timeout, $cmd)->catch (sub {
        my $error = $_[0];
        return $self->stop->then (sub {
          return $cmd->wait;
        })->then (sub {
          if ($_[0]->exit_code == 0) {
            die $error;
          } else {
            die "$error: $_[0]";
          }
        }, sub { die "$error: $_[0]" });
      });
    } else {
      return $cmd->wait->then (sub { die "Server failed to start: $_[0]" });
    }
  });
} # start

sub _stop_signal ($) {
  my $self = $_[0];
  my $server = $self->{options}->{'--server'}->[0] || '';
  return {
    Starlet => 'TERM',
    Starman => 'QUIT',
    Twiggy => 'QUIT',
    'Twiggy::Prefork' => 'TERM',
  }->{$server} || 'TERM';
} # _stop_signal

sub stop ($) {
  my $self = $_[0];
  return Promise->resolve if not defined $self->{cmd};
  my $cmd = $self->{cmd};
  return $cmd->send_signal ($self->_stop_signal)->then (sub {
    return $cmd->wait;
  })->catch (sub {
    die $_[0] if $cmd->running;
  })->then (sub {
    delete $self->{signal};
    delete $self->{cmd};
  });
} # stop

sub DESTROY ($) {
  my $cmd = $_[0]->{cmd};
  if (defined $cmd and $cmd->running and
      defined $_[0]->{start_pid} and $_[0]->{start_pid} == $$) {
    $cmd->send_signal ($_[0]->_stop_signal);
  }
} # DESTROY

1;

=head1 LICENSE

Copyright 2010-2012 Hatena <http://www.hatena.ne.jp/>.

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

package Thruk::Controller::hotspot;

use strict;
use warnings;

=head1 NAME

Thruk::Controller::hotspot - Problem Hotspots

=head1 DESCRIPTION

Problem Hotspots for services and hosts

=head1 METHODS

=cut


=head2 index

=cut

##########################################################
sub index {
    my ( $c ) = @_;

    return unless Thruk::Action::AddDefaults::add_defaults($c, Thruk::ADD_DEFAULTS);

    my($start,$end);
    my $timeframe = 86400;
    my $filter;

    my $oldestfirst = $c->req->parameters->{'oldestfirst'} || 0;
    my $archive     = $c->req->parameters->{'archive'}     || 0;
    my $type        = $c->req->parameters->{'type'}        || 0;
    my $statetype   = $c->req->parameters->{'statetype'}   || 0;
    my $noflapping  = $c->req->parameters->{'noflapping'}  || 1;
    my $nodowntime  = $c->req->parameters->{'nodowntime'}  || 1;
    my $nosystem    = $c->req->parameters->{'nosystem'}    || 1;
    my $host        = $c->req->parameters->{'host'}        || 'all';
    my $service     = $c->req->parameters->{'service'};

    if(defined $service and $host ne 'all') {
        $c->stash->{infoBoxTitle} = 'Service Alert History';
    } elsif($host ne 'all') {
        $c->stash->{infoBoxTitle} = 'Host Alert History';
    } else {
        $c->stash->{infoBoxTitle} = 'Alert History';
    }

    my $param_start = $c->req->parameters->{'start'};
    my $param_end   = $c->req->parameters->{'end'};

    # start / end date from formular values?
    if(defined $param_start and defined $param_end) {
        # convert to timestamps
        $start = Thruk::Utils::parse_date($c, $param_start);
        $end   = Thruk::Utils::parse_date($c, $param_end);
    }
    if(!defined $start || $start == 0 || !defined $end || $end == 0) {
        my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
        $start = POSIX::mktime(0, 0, 0, $mday, $mon, $year);
        $end   = $start + $timeframe;
    }
    if($archive eq '+1') {
        $start = $start + $timeframe;
        $end   = $end   + $timeframe;
    }
    elsif($archive eq '-1') {
        $start = $start - $timeframe;
        $end   = $end   - $timeframe;
    }

    # swap date if they are mixed up
    if($start > $end) {
        my $tmp = $start;
        $start = $end;
        $end   = $tmp;
    }

    # service filter
    if(defined $service and $host ne 'all') {
        push @{$filter}, { host_name => $host };
        push @{$filter}, { service_description => $service };
    }
    # host filter
    elsif($host ne 'all') {
        push @{$filter}, { host_name => $host };
    }

    # time filter
    push @{$filter}, { time => { '>=' => $start }};
    push @{$filter}, { time => { '<=' => $end }};

    # type filter
    my $typefilter = _get_log_type_filter($type);

    # normal alerts
    my @prop_filter;
    if($statetype == 0) {
        push @prop_filter, { -and => [{ type => 'SERVICE ALERT'} , $typefilter ]};
        push @prop_filter, { -and => [{ type => 'HOST ALERT'} , $typefilter ]};
    }
    elsif($statetype == 1) {
        push @prop_filter, { -and => [{ type => 'SERVICE ALERT' }, { state_type => { '=' => 'SOFT' }} , $typefilter ]};
        push @prop_filter, { -and => [{ type => 'HOST ALERT' }, { state_type => { '=' => 'SOFT' }} , $typefilter ]};
    }
    if($statetype == 2) {
        push @prop_filter, { -and => [{ type => 'SERVICE ALERT' }, { state_type=> { '=' => 'HARD' }} , $typefilter ]};
        push @prop_filter, { -and => [{ type => 'HOST ALERT' }, { state_type => { '=' => 'HARD' }} , $typefilter ]};
    }

    # join type filter together
    push @{$filter}, { -or => \@prop_filter };

    my $total_filter = Thruk::Utils::combine_filter('-and', $filter);

    my $order = "DESC";

    #my $loggs = $c->{'db'}->get_logs(filter => [$total_filter, Thruk::Utils::Auth::get_auth_filter($c, 'log')], sort => {$order => 'time'}, pager => 1);
    my $loggs = $c->{'db'}->get_logs(filter => [$total_filter, Thruk::Utils::Auth::get_auth_filter($c, 'log')], sort => {$order => 'time'});

    #Match logs - Host problems: ^\[\d+\] (HOST ALERT: )(.*);(DOWN|UP)\;(HARD|SOFT)\;(\d)\;(.*)
    #Match logs - Service problems: ^\[\d+\] (SERVICE ALERT: )(.*)\;(OK|WARNING|CRITICAL|UNKNOWN)\;(HARD|SOFT)\;(\d)\;(.*)

    my %retarr;
    for my $l (@{$loggs}) {
	if( $l->{'message'} =~ m/^\[\d+\] (SERVICE ALERT: )(.*);(WARNING|CRITICAL|UNKNOWN);(HARD|SOFT);(\d);(.*)/ ) {
	my @fields = $l->{'message'} =~ /^\[\d+\] (SERVICE ALERT: )(.*);(WARNING|CRITICAL|UNKNOWN);(HARD|SOFT);(\d);(.*)/ ;
	    $retarr{'service'}{$fields[1]}++; 
	}
	elsif( $l->{'message'} =~ m/^\[\d+\] (HOST ALERT: )(.*);(DOWN)\;(HARD|SOFT)\;(\d)\;(.*)/ ) {
	my @fields = $l->{'message'} =~ /^\[\d+\] (HOST ALERT: )(.*);(DOWN)\;(HARD|SOFT)\;(\d)\;(.*)/ ;
	    $retarr{'host'}{$fields[1]}++; 
	}

    }

my $ohotspot;
$ohotspot = "<h2>Host problems</h2>\n";
$ohotspot .= "<table class=thruk_hotspot>\n";
$ohotspot .= "<tr>\n";
$ohotspot .= "<td>Hostname</td>\n";
$ohotspot .= "<td>Problems</td>\n";
$ohotspot .= "</tr>\n";
   my $retarr_host = $retarr{'host'};
   if(scalar keys %$retarr_host > 0) {
    foreach my $problems (sort { %$retarr_host{$b} <=> %$retarr_host{$a} } keys %$retarr_host) {
       $ohotspot .= "<tr>\n";
       $ohotspot .= "<td>".$problems."</td>\n";
       $ohotspot .= "<td>".$retarr{'host'}{$problems}."</td>\n";
       $ohotspot .= "</tr>\n";
    }
   }
$ohotspot .= "</table>\n";

$ohotspot .= "<h2>Service problems</h2>\n";
$ohotspot .= "<table class=thruk_hotspot>\n";
$ohotspot .= "<tr>\n";
$ohotspot .= "<td>Service description</td>\n";
$ohotspot .= "<td>Problems</td>\n";
$ohotspot .= "</tr>\n";
   my $retarr_service = $retarr{'service'};
   if(scalar keys %$retarr_service > 0) {
    foreach my $problems (sort { %$retarr_service{$b} <=> %$retarr_service{$a} } keys %$retarr_service) {
       $ohotspot .= "<tr>\n";
       $ohotspot .= "<td>".$problems."</td>\n";
       $ohotspot .= "<td>".$retarr{'service'}{$problems}."</td>\n";
       $ohotspot .= "</tr>\n";
    }
   }
$ohotspot .= "</table>\n";


    $c->stash->{hotspotlogs}      = $ohotspot;
    $c->stash->{archive}          = $archive;
    $c->stash->{type}             = $type;
    $c->stash->{statetype}        = $statetype;
    $c->stash->{noflapping}       = $noflapping;
    $c->stash->{nodowntime}       = $nodowntime;
    $c->stash->{nosystem}         = $nosystem;
    $c->stash->{oldestfirst}      = $oldestfirst;
    $c->stash->{start}            = $start;
    $c->stash->{end}              = $end;
    $c->stash->{host}             = $host    || '';
    $c->stash->{service}          = $service || '';
    $c->stash->{title}            = 'Hotspot';
    $c->stash->{page}             = 'hotspot';
    $c->stash->{template}         = 'hotspot.tt';
    $c->stash->{'no_auto_reload'} = 1;

    return 1;
}

##########################################################
sub _get_log_type_filter {
    my ( $number ) = @_;

    $number = 0 if !defined $number || $number <= 0 || $number > 511;
    my @prop_filter;
    if($number > 0) {
        my @bits = reverse split(/\ */mx, unpack("B*", pack("N", int($number))));

        if($bits[0]) {  # 1 - All service alerts
            push @prop_filter, { service_description => { '!=' => undef }};
        }
        if($bits[1]) {  # 2 - All host alerts
            push @prop_filter, { service_description => undef };
        }
        if($bits[2]) {  # 4 - Service warning
            push @prop_filter, { state => 1, service_description => { '!=' => undef }};
        }
        if($bits[3]) {  # 8 - Service unknown
            push @prop_filter, { state => 3, service_description => { '!=' => undef }};
        }
        if($bits[4]) {  # 16 - Service critical
            push @prop_filter, { state => 2, service_description => { '!=' => undef }};
        }
        if($bits[5]) {  # 32 - Service recovery
            push @prop_filter, { state => 0, service_description => { '!=' => undef }};
        }
        if($bits[6]) {  # 64 - Host down
            push @prop_filter, { state => 1, service_description => undef };
        }
        if($bits[7]) {  # 128 - Host unreachable
            push @prop_filter, { state => 2, service_description => undef };
        }
        if($bits[8]) {  # 256 - Host recovery
            push @prop_filter, { state => 0, service_description => undef };
        }
    }
    return Thruk::Utils::combine_filter('-or', \@prop_filter);
}

=head1 AUTHOR
Sven Nierlein, 2009-present, <sven@nierlein.org>
=head1 LICENSE
This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.
=cut

1;

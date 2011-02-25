package Manoc::App::Delegate;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use Carp;

our %Handler = ();
our %AnonHandler = ();

use Attribute::Handlers;

sub Manoc::App::Delegate::Resource : ATTR(CODE,BEGIN,CHECK) {
    my ($pkg, $symbol, $referent, $attr, $data, $phase) = @_;
    no strict 'refs';
    my $name = *{$symbol}{NAME};
     
#    print STDERR	
#      ref($referent), " $name",
#	"($referent) was just declared and ascribed the ${attr} attribute ",
#	  "with data ($data) pkg $pkg in phase $phase\n";
    
    my $resource_name;
    if ($data) {
	my @args = split(/\s+/, $data);
	foreach (@args) {
	    my $keyword = lc($_);
	    
	    # special cases
	    $keyword eq 'default'
		and $Handler{$pkg}->{'--DEFAULT--'} = $referent, next;
	    $keyword eq 'error'
		and $Handler{$pkg}->{'--ERROR--'} = $referent, next;
	    
	    # register resource name
	    $Handler{$pkg}{$keyword} = $referent;
	    $resource_name = $keyword;
	}
    }

    return if defined($resource_name);

    # Get resource name from subroutine name.
    # If there is no name (e.g. running with mod_perl)
    # use anon handler to defer it to constructor
    if ($name eq 'ANON') {
	$AnonHandler{$pkg}->{"$referent"} = 1;
    } else {
	$Handler{$pkg}->{$name} = $referent;
    }

    return unless $data;

}

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};    
    bless($self, $class);

    $self->{path_info} = $args{path_info} || 1;

    # resolve anonimous handlers
    {
	no strict 'refs';
	while (my ($key,$val) = each(%{*{"$class\::"}})) {
	    local(*ENTRY) = $val;
	    if (defined $val && defined *ENTRY{CODE}) {
		my $ref =  *ENTRY{CODE};
		my $name =  (split q'::', $val)[-1];
		next unless $Manoc::App::Delegate::AnonHandler{$class}->{$ref};
		$Manoc::App::Delegate::Handler{$class}->{$name} = $ref;
		#print STDERR "Registering $val\n";
	    }
	}
	# rewind "each"
	my $a = scalar keys %{*{"$class\::"}};
    }

    return $self;
}

sub dispatch {
    my ($self, $app) = @_;

    my $path = $app->query->path_info();
    my $idx  = $self->{path_info};

    my $pi = $path;
    $idx -= 1 if ($idx > 0);
    $pi =~ s!^/!!;
    $pi = (split q'/', $path)[$idx] || '';

    if (!$pi && $path !~ q{/$} ) {
	return $app->redirect($app->query->url(-path_info=>1) . "/");
    }

    my $mode = length($pi) ? $pi : '--DEFAULT--';

    my $pkg = ref($self);
    my $handler = $Handler{$pkg}->{$mode};

    if (!defined($handler)) {
	$handler = $Handler{$pkg}->{'--ERROR--'};
	die("Resource not found (mode=$mode)") unless $handler;
    }

    return $self->$handler($app);
}

1;

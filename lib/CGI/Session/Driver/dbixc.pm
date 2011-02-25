package CGI::Session::Driver::dbixc;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use Carp;

use base CGI::Session::Driver;

sub init {
    my $self = shift;
 
    my $schema = $self->{Schema};
    unless ( $schema ) {
	return $self->set_error( "init(): missing schema");
    }

    my $rs_name = $self->{ResultSetName} || "Session";

    $self->{ResultSet} = $schema->resultset($rs_name);

    return 1;
}


sub store {
    my ($self, $sid, $datastr) = @_;
    
    croak "store(): usage error" unless $sid && $datastr;
    
    my $session = $self->{ResultSet}->update_or_create({
	id		=> $sid,
	data		=> $datastr,
	timestamp	=> time()
	});

    if ($session) {
	$session->update();
	return 1;
    }
    return $self->set_error("store: failed");
}

sub retrieve {
    my ($self, $sid) = @_;

    croak "retrieve(): usage error" unless $sid;
    
    my $session = $self->{ResultSet}->find($sid);
    return $session ? $session->data : 0;    
}

sub remove {
    my ($self, $sid) = @_;
    croak "remove(): usage error" unless $sid;

    $self->{ResultSet}->search({id => $sid})->delete_all();
    return 1;
}

sub traverse {
    my ($self, $coderef) = @_;
    croak "traverse(): usage error" 
	unless $coderef && ref($coderef) eq 'CODE';

    my $rs = $self->{ResultSet}->get_column('id')->all;
    
    while ( my $sid = $rs->next ) {
        $coderef->($sid);
    }

    return 1;
}

1;
__END__;

=pod

=head1 NAME

CGI::Session::Driver::dbixc - DBIx::Class driver

=head1 SYNOPSIS
 TODO

=cut

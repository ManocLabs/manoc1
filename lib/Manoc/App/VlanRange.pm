package Manoc::App::VlanRange;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;

my $description_length = 30;

sub list : Resource(default error){

    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my (@vlan_ranges_rs, @vlan_ranges, $template, @vlans_rs);
    my %tmpl_param;

    @vlan_ranges_rs = $schema->resultset('VlanRange')->search(
                                                                {}, 
                                                                {order_by => 'start'}
                                                             );

    @vlans_rs = $schema->resultset('Vlan')->all();

    @vlan_ranges = map {
                    id              => $_->id,
                    name            => $_->name,
                    start           => $_->start,
                    end             => $_->end,
                    description     => short_descr($_->description, $description_length), 
                    n_neighs        => scalar(get_neighbours ($schema, $_)) > 0 ? 1 : 0,
                    vlans           => get_vlans($app, $_->id, @vlans_rs),
                    add_vlan_url    => $app->manoc_url("vlan/new_vlan?forced_range_id=" . $_->id . "&origin=vlanrange/list"),
                    edit_url        => "edit?id=". $_->id,
                    split_url       => "split?id=". $_->id,
                    merge_url       => "merge?id=". $_->id,
                    delete_url      => "delete?id=". $_->id
                 }, @vlan_ranges_rs;

    $tmpl_param{ranges} 		= \@vlan_ranges;
    $tmpl_param{new_vlanrange_url}	= $app->manoc_url("vlanrange/create");

    $template = $app->prepare_tmpl(	
	tmpl  => 'vlanrange/list.tmpl',
	title => 'Vlan Ranges'
	); 
    $template->param(%tmpl_param);

    return $template->output();
}

sub view :Resource {

    my ($self, $app) = @_;
    my $schema  = $app->param('schema');
    my $query   = $app->query;
    my $id      = $query->param('id');
    my (%tmpl_param, $vlan_range, @vlans_rs, @vlans);

    $vlan_range = $schema->resultset('VlanRange')->find({'id'=>$id});
    (!defined($vlan_range)) and return $app->show_message('Error', 'Vlan Range not found');

    @vlans_rs = $schema->resultset('Vlan')->search({'vlan_range' => $id});
    @vlans = map {
                    id => $_->id,
                    name => $_->name
                  }, @vlans_rs;

    #Set template parameters
    $tmpl_param{name}         = $vlan_range->name;
    $tmpl_param{start}        = $vlan_range->start;
    $tmpl_param{end}          = $vlan_range->end;
    $tmpl_param{description}  = $vlan_range->description;
    $tmpl_param{vlans}        = \@vlans;
    $tmpl_param{n_neighs}     = scalar(get_neighbours ($schema, $vlan_range)) > 0 ? 1 : 0;
    $tmpl_param{add_vlan_url} = $app->manoc_url("vlan/new_vlan?forced_range_id=" . $id . "&origin=vlanrange/view?id=$id");
    $tmpl_param{edit_url}     = "edit?id=$id";
    $tmpl_param{split_url}    = "split?id=$id";
    $tmpl_param{merge_url}    = "merge?id=$id";
    $tmpl_param{delete_url}   = "delete?id=$id";

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/view.tmpl',
					title => 'Vlan Range ' . $vlan_range->name
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub create : Resource{

    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");

    my $schema      = $app->param('schema');
    my $query       = $app->query;
    my (%tmpl_param, $done, $message);

    #Call the new vlan subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_new_vlanrange($app);
        if ($done){
           return $app->manoc_redirect("vlanrange");
        }
    }

    #Set template parameters
    $tmpl_param{message}      = $message;
    $tmpl_param{name}         = $query->param('name');
    $tmpl_param{start}        = $query->param('start');
    $tmpl_param{end}          = $query->param('end');
    $tmpl_param{description}  = $query->param('description');

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/edit.tmpl',
					title => 'New Vlan Range'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_new_vlanrange{

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $id              = $query->param('id');
    my $name            = $query->param('name');
    my $start           = $query->param('start');
    my $end             = $query->param('end');
    my $description     = $query->param('description');
    my ($res, $message);

    ($res, $message) = check_parameters($schema, $id, $name, $start, $end);
    $res or return ($res, $message);

    $schema->resultset('VlanRange')->create({
                                                name        => $name,
                                                start       => $start,
                                                end         => $end,
                                                description => $description
                                            }) or return(0, "Impossible create Vlan");

    return (1, "Done");
}

sub edit : Resource{

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema      = $app->param('schema');
    my $query       = $app->query;
    my $id          = $query->param('id');
    my ($name, $start, $end, $description);
    my (%tmpl_param, $vlan_range, $done, $message);

    #Call the edit vlan range subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_edit($app);
        if ($done){
           return $app->manoc_redirect("vlanrange");
        }
    }

    #Retrieve vlan range attributes
    $vlan_range = $schema->resultset('VlanRange')->find('id' => $id);
    (!defined($vlan_range)) and return $app->show_message('Error', 'Vlan Range not found');
    $name        = $vlan_range->name;
    $start       = $vlan_range->start;
    $end         = $vlan_range->end;
    $description = $vlan_range->description;

    #Set template parameters
    $tmpl_param{message}      = $message;
    $tmpl_param{id}           = $id;
    $tmpl_param{name}         = $name;
    $tmpl_param{start}        = $start;
    $tmpl_param{end}          = $end;
    $tmpl_param{description}  = $description;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/edit.tmpl',
					title => 'Edit Vlan Range'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_edit{

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $id              = $query->param('id');
    my $name            = $query->param('name');
    my $start           = $query->param('start');
    my $end             = $query->param('end');
    my $description     = $query->param('description');
    my ($vlan_range, @cov_vlans, $res, $message);

    #Check parameters
    ($res, $message) = check_parameters($schema, $id, $name, $start, $end);
    $res or return ($res, $message);

    #Check vlan coverage
    @cov_vlans = $schema->resultset('Vlan')->search({vlan_range => $id});
    foreach (@cov_vlans) {
        ($_->id < $start or $_->id > $end) and return (0, "Invalid range: vlan " . $_->name . " not covered by the range");
    }

    #Update values
    $vlan_range = $schema->resultset('VlanRange')->find({id => $id});
    $vlan_range->name($name);
    $vlan_range->start($start);
    $vlan_range->end($end);
    $vlan_range->description($description);
    $vlan_range->update or return(0, "Impossible edit Vlan Range");

    return (1, "Done");
}

sub split_vlanrange : Resource("split"){

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $id           = $query->param('id');
    my $name1        = $query->param('name1');
    my $name2        = $query->param('name2');
    my $split_point  = $query->param('split_point');
    my (%tmpl_param, $vlan_range, $done, $message);

    #Call the split vlan range subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_split_vlanrange($app);
        if ($done){
           return $app->manoc_redirect("vlanrange");
        }
    }

    #Retrieve vlan range attributes
    $vlan_range = $schema->resultset('VlanRange')->find('id' => $id);
    (!defined($vlan_range)) and return $app->show_message('Error', 'Vlan Range not found');

    #Set template parameters
    $tmpl_param{message}      = $message;
    $tmpl_param{id}           = $id;
    $tmpl_param{name}         = $vlan_range->name;
    $tmpl_param{start}        = $vlan_range->start;
    $tmpl_param{end}          = $vlan_range->end;
    $tmpl_param{name1}        = $name1;
    $tmpl_param{name2}        = $name2;
    $tmpl_param{split_point}  = $split_point;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/split.tmpl',
					title => 'Split Vlan Range'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_split_vlanrange {

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $id              = $query->param('id');
    my $name1           = $query->param('name1');
    my $name2           = $query->param('name2');
    my $split_point     = $query->param('split_point');
    my ($vlan_range, $vlan_range1, $vlan_range2, @vlans, $res, $message);

    #Get parent vlan range values
    $vlan_range = $schema->resultset('VlanRange')->find('id' => $id);

    #Check names
    ($res, $message) = check_name ($schema, undef, $name1);
    $res or return ($res, $message);
    ($res, $message) = check_name ($schema, undef, $name2);
    $res or return ($res, $message);
    ($name1 eq $name2) and return (0, "Vlan range names can't be the same");

    #Check split point
    ($split_point >= $vlan_range->start and $split_point < $vlan_range->end) 
        or return (0, "Split point must be inside " . $vlan_range->name . " vlan range");

    #Update DB (with a transaction)
    $schema->txn_do( sub {
        $vlan_range1 = $schema->resultset('VlanRange')->create({
                                                                    name        => $name1,
                                                                    start       => $vlan_range->start,
                                                                    end         => $split_point
                                                            }) or return(0, "Impossible split Vlan");
        $vlan_range2 = $schema->resultset('VlanRange')->create({
                                                                    name        => $name2,
                                                                    start       => $split_point + 1,
                                                                    end         => $vlan_range->end
                                                            }) or return(0, "Impossible split Vlan");

        @vlans = $schema->resultset('Vlan')->search('vlan_range' => $id);
        foreach (@vlans) {
            if ($_->id >= $vlan_range->start and $_->id <= $split_point) {
                $_->vlan_range($vlan_range1->id);
            } else {
                $_->vlan_range($vlan_range2->id);
            }
            $_->update;
        }

        $vlan_range->delete or return(0, "Impossible split Vlan");
    });
    
    if ($@) {
        my $commit_error = $@;
        return (0, "Impossible update database: $commit_error");
    }

    return (1, "Done");
}

sub merge_vlanrange : Resource("merge"){

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema            = $app->param('schema');
    my $query             = $app->query;
    my $id                = $query->param('id');
    my $sel_vlan_range_id = $query->param('sel_vlan_range_id');
    my $new_name          = $query->param('new_name');
    my (%tmpl_param, $vlan_range, @neigh_rs, @neighs, $done, $message);

    #Call the split vlan range subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_merge_vlanrange($app);
        if ($done){
           return $app->manoc_redirect("vlanrange");
        }
    }

    #Retrieve vlan range attributes
    $vlan_range = $schema->resultset('VlanRange')->find('id' => $id);
    (!defined($vlan_range)) and return $app->show_message('Error', 'Vlan Range not found');

    @neigh_rs = get_neighbours($schema, $vlan_range);
    if (@neigh_rs) {
        @neighs = map {
                        id       => $_->id,
                        name     => $_->name,
                        start    => $_->start,
                        end      => $_->end,
                        checked  => $sel_vlan_range_id eq $_->id
                      }, @neigh_rs;
    }

    #Set template parameters
    $tmpl_param{message}        = $message;
    $tmpl_param{id}             = $id;
    $tmpl_param{name}           = $vlan_range->name;
    $tmpl_param{start}          = $vlan_range->start;
    $tmpl_param{end}            = $vlan_range->end;
    $tmpl_param{neighs}         = \@neighs;
    $tmpl_param{sel_vlan_range} = $sel_vlan_range_id;
    $tmpl_param{new_name}       = $new_name;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/merge.tmpl',
					title => 'Merge Vlan Range'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_merge_vlanrange {

    my ($self, $app)      = @_;
    my $schema            = $app->param('schema');
    my $query             = $app->query;
    my $id                = $query->param('id');
    my $sel_vlan_range_id = $query->param('sel_vlan_range_id');
    my $new_name          = $query->param('new_name');
    my ($vlan_range, $neigh, $new_vlan_range, @vlans, $res, $message);

    #Get vlan range values
    $vlan_range = $schema->resultset('VlanRange')->find('id' => $id);

    #Check new vlan range name
    ($res, $message) = check_name ($schema, undef, $new_name);
    $res or return ($res, $message);

    #Check neighbour
    $neigh = $schema->resultset('VlanRange')->find('id' => $sel_vlan_range_id);
    $neigh or return (0, "Invalid neighbour vlan range");

    #Update DB (with a transaction)
    $schema->txn_do( sub {
        $new_vlan_range = $schema->resultset('VlanRange')->create({
                                                                        name        => $new_name,
                                                                        start       => $vlan_range->start < $neigh->start ? $vlan_range->start : $neigh->start,
                                                                        end         => $vlan_range->end > $neigh->end ? $vlan_range->end : $neigh->end
                                                                  }) or return(0, "Impossible merge Vlan");

        @vlans = $schema->resultset('Vlan')->search([
                                                        {'vlan_range' => $id},
                                                        {'vlan_range' => $sel_vlan_range_id}
                                                    ]);
        foreach (@vlans) {
            $_->vlan_range($new_vlan_range->id);
            $_->update;
        }

        $vlan_range->delete or return(0, "Impossible merge Vlan");
        $neigh->delete or return(0, "Impossible merge Vlan");
    });
    
    if ($@) {
        my $commit_error = $@;
        return (0, "Impossible update database: $commit_error");
    }

    return (1, "Done");
}

sub delete : Resource{

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $id           = $query->param('id');
    my (@vlan_rs, $message); 

    my $vlan_range = $schema->resultset('VlanRange')->find($id);
    (!defined($vlan_range)) and return $app->show_message('Error', 'Vlan Range not found');

    @vlan_rs = $schema->resultset('Vlan')->search('vlan_range' => $id);
    @vlan_rs and return warning_delete($app, @vlan_rs);

    $vlan_range->delete() or return(0, "Impossible delete vlan range");

    return $app->manoc_redirect("vlanrange");
}

sub warning_delete {
    my ($app, @vlan_rs) = @_;
    my (@vlans, %tmpl_param);

    @vlans = map {
                    id => $_->id,
                    name => $_->name
                  }, @vlan_rs;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlanrange/warning_delete.tmpl',
					title => 'Warning!'
 				     ); 
    $template->param(vlans => \@vlans);
    $template->param(vlanrange_url => $app->manoc_url("vlanrange"));

    return $template->output();
}

sub check_parameters {

    my ($schema, $id, $name, $start, $end) = @_;
    my $min_vlan_value  = 1;
    my $max_vlan_value  = 4094;
    my ($dup, $conditions, @overlap_rs, $res, $message);

    #Check parameters
    $name or return (0, "Please insert vlan range name");
    $start or return (0, "Please insert vlan range start");
    $end or return (0, "Please insert vlan range end");

    ($res, $message) = check_name ($schema, $id, $name);
    $res or return ($res, $message);

    #Check start and end values
    $start =~ /^\d+$/ or return(0, "Invalid start value");
    ($start >= $min_vlan_value and $start <= $max_vlan_value) or return (0, "Invalid start value");
    $end =~ /^\d+$/ or return(0, "Invalid end value");
    ($end >= $min_vlan_value and $end <= $max_vlan_value) or return (0, "Invalid end value");
    $start <= $end or return(0, "Invalid vlan range");

    #Check overlapping
    $conditions = [
		      {
			  start	=> { '<=' => $start },
			  end	=> { '>=' => $start }
		      },
		      {
			  start	=> { '<=' => $end },
			  end	=> { '>=' => $end }
		      },
		      {
			  start	=> { '>=' => $start },
			  end	=> { '<=' => $end }
		      },
		  ];
    @overlap_rs = $schema->resultset('VlanRange')->search($conditions);
    if (@overlap_rs){
        ((scalar @overlap_rs == 1) and ($overlap_rs[0]->id eq $id)) or 
            return(0, "Invalid vlan range: overlaps with ". $overlap_rs[0]->name . qq/ (/ . $overlap_rs[0]->start . qq/ - / . $overlap_rs[0]->end . qq/)/);
    }

    return (1, "Ok");
}

sub check_name {

    my ($schema, $id, $name) = @_;

    my $dup = $schema->resultset('VlanRange')->find('name' => $name);
    if ($dup) {$dup->id == $id or return (0, "Duplicated vlan range name: $name");}
    $name =~ /^\w[\w-]*$/ or return (0, "Invalid vlan range name: $name");
}

sub get_neighbours {

    my ($schema, $vlan_range) = @_;

    return $schema->resultset('VlanRange')->search([
                                                {end => $vlan_range->start - 1},
                                                {start => $vlan_range->end + 1}
                                            ]);
}

sub get_vlans {

    my ($app, $range_id, @vlans_rs) = @_;
    my @vlans;

    foreach (@vlans_rs){
        if ($_->vlan_range->id == $range_id){
            push @vlans, {
                            id          => $_->id,
                            name        => $_->name,
                            description => short_descr($_->description, $description_length),
                            edit_url    => $app->manoc_url("vlan/edit?id=". $_->id . "&origin=vlanrange/list"),
                            delete_url  => $app->manoc_url("vlan/delete?id=". $_->id . "&origin=vlanrange/list")
                         }
        } 
    }

    return \@vlans;
}

sub short_descr {
    my ($description, $len) = @_;
    my $s_descr;
    
    if (defined $description) {
        $s_descr = substr($_->description, 0, $len);
        (length($description) > $len) and $s_descr .= "...";
    } else {
        return undef;
    }
    
    return $s_descr;
}

1;

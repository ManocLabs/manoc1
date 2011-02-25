use strict;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.
use warnings;

package Manoc::DB;

use base qw/DBIx::Class::Schema/;
__PACKAGE__->load_namespaces();

1;

package Manoc::Taglib;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

=head1 NAME

Manoc::Taglib - HTML::Template additional tags for Manoc

=head1 SEE ALSO

HTML::Template

=cut

use base qw(Class::Data::Inheritable);

__PACKAGE__->mk_classdata('base_url');
__PACKAGE__->mk_classdata('img_base_url');



sub filter  {
    my $text_ref = shift;
   
    my $img_base   = __PACKAGE__->img_base_url;
    my $manoc_base = __PACKAGE__->base_url;
    my $manoc      = "$manoc_base/manoc";

    # <manoc_link device id=NAME> 
    $$text_ref =~ s{<manoc_link
			\s+
			device
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted device id
			\/?>
		    }{<a href="$manoc/device/view?id=<tmpl_var name=$1>"><tmpl_var name=$1></a><a href="telnet:<tmpl_var name=$1>"><img class="shortcut" border="0" src="$img_base/telnet.gif" alt="telnet" /></a>
		    }gsx;
    
    # <manoc_link iface device=ID iface=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			iface
			\s+
			device\s*=\s*	
			([^\s=>]*)  # $1 => unquoted device name
			\s+
			iface\s*=\s*
			([^\s=>]*)  # $2 => unquoted interface name
			\/?>
		    }{<a href="$manoc/interface?device=<tmpl_var name=$1>&iface=<tmpl_var name=$2>"><tmpl_var name=$1>/<tmpl_var name=$2></a>}gsx;

    # <manoc_link iface device=ID iface=NAME short>
    $$text_ref =~ s{<manoc_link
			\s+
			iface
			\s+
			device\s*=\s*	
			([^\s=>]*)  # $1 => unquoted device name
			\s+
			iface\s*=\s*	
			([^\s=>]*)  # $2 => unquoted interface name
			\s+
			short
			\/?>
		    }{<a href="$manoc/interface?device=<tmpl_var name=$1>&iface=<tmpl_var name=$2>"><tmpl_var name=$2></a>}gsx;

    # <manoc_link (rack|building) id=ID name=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			(rack|building)  # $1 => type
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $2 => unquoted id
                        \s+
			name\s*=\s*
			([^\s=>]*)  # $3 => unquoted name
			\/?>
		    }{<a href="$manoc/$1/view?id=<tmpl_var name=$2>"><tmpl_var name=$3></a>}gsx;

    # <manoc_link (ip|mac) id=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			(ip|mac)  # $1 => type
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $2 => unquoted id
			\/?>
		    }{<a href="$manoc/$1?id=<tmpl_var name=$2>"><tmpl_var name=$2></a>}gsx;
   
    # <manoc_link iprange id=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			(iprange)  # $1 => type
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $2 => unquoted id
			\/?>
		    }{<a href="$manoc/iprange/view?name=<tmpl_var name=$2>"><tmpl_var name=$2></a>}gsx;

    # <manoc_link vlan id=ID>
    $$text_ref =~ s{<manoc_link
			\s+
			vlan 
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted id
			\/?>
		    }{<a href="$manoc/vlan/view?id=<tmpl_var name=$1>"><tmpl_var name=$1></a>}gsx;

    # <manoc_link vlan id=ID name=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			vlan 
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted id
                        \s+
			name\s*=\s*
			([^\s=>]*)  # $2 => unquoted vlan name
			\/?>
		    }{<a href="$manoc/vlan/view?id=<tmpl_var name=$1>"><tmpl_var name=$2></a>}gsx;

    # <manoc_link vlanrange id=ID name=NAME>
    $$text_ref =~ s{<manoc_link
			\s+
			vlanrange
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted vlanrange id
			\s+
			name\s*=\s*
			([^\s=>]*)  # $2 => unquoted vlanrange name
			\/?>
		    }{<a href="$manoc/vlanrange/view?id=<tmpl_var name=$1>"><tmpl_var name=$2></a>}gsx;

     # <manoc_link ssid id=ID>
    $$text_ref =~ s{<manoc_link
			\s+
			ssid
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted vlanrange id
			\/?>
		    }{<a href="$manoc/ssid/info?ssid=<tmpl_var name=$1>"><tmpl_var name=$1></a>}gsx;

 # <manoc_link subnet id=ID>
    $$text_ref =~ s{<manoc_link
			\s+
			subnet
			\s+
			id\s*=\s*	
			([^\s=>]*)  # $1 => unquoted vlanrange id
			\/?>
		    }{<a href="$manoc/iprange/view?name=<tmpl_var name=$1>"><tmpl_var name=$1></a>}gsx;

    # <manoc_icon edit|view|remove|note|new|split|merge|ok|no|void>
    $$text_ref =~ s{<manoc_icon
			\s+
			(add|new|edit|view|remove|note|split|merge|ok|no|void)  # $1 => name
			\s*
			\/?>
		    }{<img class="shortcut" border="0" src="$img_base/$1.gif" alt="$1" title="$1"/>}gsx;

    # <manoc_icon (edit|view|remove|note|new|split|merge|ok|no)_white>
    $$text_ref =~ s{<manoc_icon
			\s+
			(edit_white|remove_white|split_white|merge_white|ok_white|no_white)  # $1 => name
			\s*
			\/?>
		    }{<img class="shortcut" border="0" src="$img_base/$1.gif" alt="$1"/>}gsx;
	
	# <manoc_bar link=LINK colspan=COLSPAN text=TEXT>
    $$text_ref =~ s{<manoc_bar
			\s+
			link\s*=\s*	
			([^\s=>]*)  # $1 => unquoted link
			\s+
			colspan\s*=\s*	
			([^\s=>]*)  # $2 => unquoted colspan
			\s+
			text\s*=\s*
			"([^=>]*)"  # $3 => quoted link text
			\/?>
		    }{<tr align=right bgcolor=#99CCFF>
				<td colspan=$2>
					<a href="<tmpl_var name=$1>"><img class="shortcut" border="0" src="$img_base/add.gif" alt="add" title="add"/><font size=2> $3 </font></a>
				</td>
			  </tr>}gsx;
    
    # <manoc_bar link1=LINK1 link2=LINK2 text1=TEXT1 text2=TEXT2 colspan=COLSPAN noicon>
    $$text_ref =~ s{<manoc_bar
			\s+
			link1\s*=\s*	
			([^\s=>]*)  # $1 => unquoted link
            \s+
            link2\s*=\s*	
			([^\s=>]*)  # $2 => unquoted link
			\s+
			text1\s*=\s*
			"([^=>]*)"  # $3 => quoted link text
            \s+
            text2\s*=\s*
			"([^=>]*)"  # $4 => quoted link text
            \s+
            colspan\s*=\s*	
			([^\s=>]*)  # $5 => unquoted colspan
			\s+
			noicon
			\/?>
		    }{<tr align=right bgcolor=#99CCFF>
				<td colspan=$5>
					<a href="<tmpl_var name=$1>"><font size=2> $3 </font></a>
                    &nbsp&nbsp&nbsp&nbsp&nbsp
                    <a href="<tmpl_var name=$2>"><font size=2> $4 </font></a>
				</td>
			  </tr>}gsx;

}

1;

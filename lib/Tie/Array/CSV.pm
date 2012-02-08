package Tie::Array::CSV;

use strict;
use warnings;

use Carp;

use Tie::File;
use Text::CSV;

use Tie::Array;
our @ISA = ('Tie::Array');

sub parse_opts {
  my $class = shift;

  croak "Must specify a file" unless @_;

  my ($file, %opts);

  # handle one arg as either hashref (of opts) or file
  if (@_ == 1) {
    if (ref $_[0] eq 'HASH') {
      %opts = %{ shift() };
    } else {
      $file = shift;
    }
  }

  # handle file and hashref of opts
  if (@_ == 2 and ref $_[1] eq 'HASH') {
    $file = shift;
    %opts = %{ shift() };
  }

  # handle file before hash of opts
  if (@_ % 2) {
    $file = shift;
  }

  # handle hash of opts
  if (@_) {
    %opts = @_;
  }

  # handle file passed has hash(ref) value to 'file' key
  if (!$file and defined $opts{file}) {
    $file = delete $opts{file};
  }

  # file wasn't specified as lone arg or as a hash opt
  croak "Must specify a file" unless $file;

  # parse specific options
  if (exists $opts{sep_char}) {
    $opts{text_csv}{sep_char} = delete $opts{sep_char};
  }

  return ($file, \%opts);
}

sub new {
  my $class = shift;
  my ($file, $opts) = $class->parse_opts(@_);

  my @self;
  tie @self, $class, $file, $opts;

  return \@self;

}

sub TIEARRAY {
  my $class = shift;
  my ($file, $opts) = $class->parse_opts(@_);

  my @tiefile;
  tie @tiefile, 'Tie::File', $file, %{ $opts->{tie_file} || {} }
    or croak "Cannot tie file $file";

  my $csv = Text::CSV->new($opts->{text_csv} || {}) 
    or croak "CSV (new) error: " . Text::CSV->error_diag();

  my $self = {
    file => \@tiefile,
    csv => $csv,
  };

  bless $self, $class;

  return $self;
}

sub FETCH {
  my $self = shift;
  my $index = shift;

  my $line = $self->{file}[$index];

  my $rowclass = ref($self) . '::Row';
  tie my @line, $rowclass, { 
    file => $self->{file},
    line_num => $index,
    fields => $self->_parse($line), 
    csv => $self->{csv},
  };

  return \@line;
}

sub STORE {
  my $self = shift;
  my ($index, $value) = @_;

  $self->{file}[$index] = $self->_combine($value);
}

sub FETCHSIZE {
  my $self = shift;

  return scalar @{ $self->{file} };
}

sub STORESIZE {
  my $self = shift;
  my $new_size = shift;

  $#{ $self->{file} } = $new_size - 1;
  
}

sub EXISTS { 
  my $self = shift;
  my ($index) = shift;
  return exists $self->{file}[$index];
}

sub DELETE { 
  my $self = shift;
  my $index = shift;
  return $self->SPLICE($index,1);
}

sub _parse {
  my $self = shift;
  my ($line) = @_;

  $self->{csv}->parse($line)
    or croak "CSV parse error: " . $self->{csv}->error_diag();

  return [$self->{csv}->fields];
}

sub _combine {
  my $self = shift;
  my ($value) = @_;

  $self->{csv}->combine( ref $value ? @$value : ($value) )
    or croak "CSV combine error: " . $self->{csv}->error_diag();

  return $self->{csv}->string;
}

package Tie::Array::CSV::Row;

use Carp;

use Tie::Array;
our @ISA = ('Tie::Array');

use overload 
  '@{}' => sub{ $_[0]{fields} };

sub TIEARRAY {
  my $class = shift;
  my $self = shift;

  bless $self, $class;

  return $self;
}

sub FETCH {
  my $self = shift;
  my $index = shift;

  return $self->{fields}[$index];
}

sub STORE {
  my $self = shift;
  my ($index, $value) = @_;

  $self->{fields}[$index] = $value;

  $self->_update;

}

sub FETCHSIZE {
  my $self = shift;

  return scalar @{ $self->{fields} };
}

sub STORESIZE {
  my $self = shift;
  my $new_size = shift;

  my $return = (
    $#{ $self->{fields} } = $new_size - 1
  );

  $self->_update;

  return $return;
}

sub SHIFT {
  my $self = shift;

  my $value = shift @{ $self->{fields} };

  $self->_update;

  return $value;
}

sub UNSHIFT {
  my $self = shift;
  my $value = shift;

  unshift @{ $self->{fields} }, $value;

  $self->_update;

  return $self->FETCHSIZE();
}

sub DELETE {
  my $self = shift;
  my $index = shift;

  my $return = splice @{ $self->{fields} }, $index, 1;
  $self->_update;

  return $return;
}

sub EXISTS {
  my $self = shift;
  my $index = shift;

  return exists $self->{fields}[$index];
}

sub _update {
  my $self = shift;

  $self->{csv}->combine(@{ $self->{fields} })
    or croak "CSV combine error: " . $self->{csv}->error_diag();
  $self->{file}[$self->{line_num}] = $self->{csv}->string;
}

__END__
__POD__

=head1 NAME

Tie::Array::CSV::HoldRow - A tied array which combines the power of Tie::File and Text::CSV

=head1 SYNOPSIS

 use strict; use warnings;
 use Tie::Array::CSV::HoldRow;
 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename';

 print $file[0][2];
 $file[3][5] = "Camel";

=head1 DESCRIPTION

This module allows an array to be tied to a CSV file for reading and writing. The array is a standard Perl 2D array (i.e. an array of array references) which gives access to the row and column of the user's choosing. This is done using the well established modules:

=over

=item * 
L<Tie::File>

=over

=item *

arbitrary line access

=item *

low memory use even for large files

=back

=item *

L<Text::CSV> 

=over

=item *

row parsing

=item *

row updating

=item *

uses the speedy L<Text::CSV_XS> if installed

=back

=back

This module was inspired by L<Tie::CSV_File> which (sadly) hasn't been maintained. It also doesn't attempt to do any of the parsing (as that module did), but rather passes all of the heavy lifting to other modules.

Note that while the L<Tie::File> prevents the need to read in the entire file, while in use, a parsed row IS held in memory. This is true whether C<hold_row> is in effect or not (see L</Options> below).

=head1 CONSTRUCTORS

Since version 0.04 both constructors allow the options that version 0.03 only offered for the C<new> constructor. The constructors must be passed a file name, either as the first argument, or as the value to the option key C<file>. Options may be passed as key-value pairs or as a hash reference. This yields the many ways of calling the constructors shown below, one for every taste.

N.B. Should a lone argument filename and a C<file> option key both be passed to the constructor, the lone argument wins.

=head2 C<tie> Constructor

As with any tied array, the construction uses the C<tie> function. Basic usage is as follows:

 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename';

which would tie the lexically scoped array C<@file> to the file C<filename> using this module. Following the first two arguements to C<tie>, one may optionally pass a key-value pairs or a hashref containing additional configuration or even file specification.

 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename', { opt_key => val, ... };
 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename', opt_key => val, ... ;
 tie my @file, 'Tie::Array::CSV::HoldRow', { file => 'filename', opt_key => val, ... };
 tie my @file, 'Tie::Array::CSV::HoldRow', file => 'filename', opt_key => val, ... ;

Of course, the magical Perl C<tie> can be scary for some, for those people there is the ...

=head2 C<new> Constructor

[ Added in version 0.03 ]

 my $array = Tie::Array::CSV::HoldRow->new( 'filename' );
 my $array = Tie::Array::CSV::HoldRow->new( 'filename', { opt_key => val, ... });
 my $array = Tie::Array::CSV::HoldRow->new( 'filename', opt_key => val, ... );
 my $array = Tie::Array::CSV::HoldRow->new( file => 'filename', opt_key => val, ... );
 my $array = Tie::Array::CSV::HoldRow->new( { file => 'filename', opt_key => val, ... } );

It only returns a reference to the C<tie>d array due to a limitations in how C<tie> magic works. 

=head2 Options

=over

=item *

C<file> - alternative method for specifing the file to C<tie>. This is overridden by a lone filename or handle passed as the first argument to the constructor.

=item *

C<tie_file> - hashref of options which are passed to the L<Tie::File> constructor

=item *

C<text_csv> - hashref of options which are passed to the L<Text::CSV> constructor

=item *

C<sep_char> - for ease of use, a C<sep_char> option may be specified, which is passed to the L<Text::CSV> constructor. This option overrides a corresponding entry in the C<text_csv> pass-through hash.

=item *

C<hold_row> - If true, the file is not updated while the reference to the row is still in scope. The default is true. Note: that when false, the parsed row is still held in memory while the row is in scope, the ONLY difference is that the file reflects changes immediately when C<hold_row> is false. To reiterate, this option only affects file IO, not memory usage.

When multiple rows are kept alive/removed/modified there was the possibility that conflicting directives could be given to a single physical line. To combat this possibility, as of version 0.05, all (living) child row objects are made aware of line number changes in the parent (outer array) should these occur. Futher if a row object is alive, but the parent object removes that line, the row object is remains intact, but the links between the row object and parent/file are severed.

=back

Equivalent examples:

 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename', { 
   tie_file => {}, 
   text_csv => { sep_char => ';' },
   hold_row => 0
 };

 tie my @file, 'Tie::Array::CSV::HoldRow', 'filename', sep_char => ';', hold_row => 0;

=head1 ERRORS

For simplicity this module C<croak>s on all almost all errors, which are trappable using a C<$SIG{__DIE__}> handler. Modifing a severed row object issues a warning.

=head1 CAVEATS

=over 

=item *

Much of the functionality of normal arrays is mimicked using L<Tie::Array>. The interaction of this with L<Tie::File> should be mentioned in that certain actions may be very inefficient. For example, C<(un)shift>-ing the first row of data will probably involve L<Tie::Array> asking L<Tie::File> to move each row up one line, one-by-one. As a note, the intra-row C<(un)shift> does not suffer this problem.

=item *

Some effort had been made to allow for fields which contain linebreaks. Linebreaks would change line numbers used for row access by L<Tie::File>. This, unfortunately, moved the module far from its stated goals, and therefore far less powerful for its intended purposes. The decision has been made (for now) not to support such files.

=back

=head1 SEE ALSO

=over

=item *

L<Tie::CSV_File> - inspiration for this module, but problematic

=item *

L<Tie::Array::DBD> - tie database connection to array

=item *

L<Tie::DBI> - similar but hash based

=back

=head1 SOURCE REPOSITORY

L<http://github.com/jberger/Tie-Array-CSV>

=head1 AUTHOR

Joel Berger, E<lt>joel.a.berger@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Joel Berger

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


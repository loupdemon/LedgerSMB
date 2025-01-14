
package LedgerSMB::Scripts::taxform;

=head1 NAME

LedgerSMB::Scripts::taxform - LedgerSMB handler for reports on tax forms.

=head1 DESCRIPTION

Implement the ability to do end-of-year reporting on vendors as to how
much was recorded as reportable.

1) A summary report vs a detail report. 2) On the summary report, clicking
through brings you to a detail report for that vendor. 3) On the detail
report, clicking through brings you to the contact/account or invoice
information depending on what one clicks.

=head1 METHODS

=cut

use strict;
use warnings;

use HTTP::Status qw( HTTP_OK );

use LedgerSMB::DBObject::TaxForm;
use LedgerSMB::Form;
use LedgerSMB::Report::Taxform::Summary;
use LedgerSMB::Report::Taxform::Details;
use LedgerSMB::Report::Taxform::List;
use LedgerSMB::Setting;
use LedgerSMB::Template;
use LedgerSMB::Template::UI;

our $VERSION = '1.0';


=pod

=over

=item report

Display the filter screen.

=cut

sub report {
    use LedgerSMB::Scripts::reports;
    my ($request) = @_;
    $request->{report_name} = 'taxforms';

    # Get tax forms.
    my $taxform = LedgerSMB::DBObject::TaxForm->new(%$request);
    $taxform->get_forms();
    $request->{forms} = $taxform->{forms};
    return LedgerSMB::Scripts::reports::start_report($request);
}

=pod

=item add_taxform

Display the "add taxform" screen.

=cut

sub _taxform_screen
{
    my ($request) = @_;
    my $taxform = LedgerSMB::DBObject::TaxForm->new(%$request);
    $taxform->{countries} = $request->enabled_countries;
    $taxform->{default_country} =
        LedgerSMB::Setting->new(%$request)->get('default_country');

    my $template = LedgerSMB::Template::UI->new_UI;
    return $template->render($request, 'taxform/add_taxform', $taxform);
}

sub add_taxform {
    return _taxform_screen(@_);
}

=item edit

This retrieves and edits a tax form.  Requires that id be set.

=cut

sub edit {
    my ($request) = @_;
    my $tf =
        LedgerSMB::DBObject::TaxForm->new(%$request)
        ->get($request->{id});
    $request->{$_} = $tf->{$_} for keys %$tf;
    return _taxform_screen($request);
}

=item generate_report

Generates the summary or detail report.   Query inputs (required unless
otherwise specified:

=over

=item begin
Begin date

=item end
End date

=item taxform_id
ID of tax form

=item meta_number (optional)
Vendor or customer account number.  If set, triggers detailed report instead
of summary for all customers/vendors associated with the tax form.

=back

In the future the actual report routines will be wrapped in a taxform_report
package.

=cut

sub generate_report {
    my ($request) = @_;
    die $request->{_locale}->text('No tax form selected')
        unless $request->{tax_form_id};

    my $report;
    if ($request->{meta_number}){
        $report = LedgerSMB::Report::Taxform::Details->new(%$request);
    } else {
        $report = LedgerSMB::Report::Taxform::Summary->new(%$request);
    }
    return $request->render_report($report);
}

=item save

Saves a tax form, returns to edit screen.

=cut


sub save
{
    my ($request) = @_;
    my $taxform = LedgerSMB::DBObject::TaxForm->new(%$request);

    $taxform->save();
    return edit($taxform);
}

=item print

Prints the tax forms, using the 1099 templates.

=cut

sub print {
    my ($request) = @_;
    my $taxform = LedgerSMB::DBObject::TaxForm->new(%$request);
    my $form_info = $taxform->get($request->{tax_form_id});
    $request->{taxform_name} = $form_info->{form_name};
    $request->{format} = 'PDF';
    my $report = LedgerSMB::Report::Taxform::Summary->new(%$request);
    $report->run_report($request);
    if ($request->{meta_number}){
       my @rows = $report->rows;
       my $inc = 0;
       for (@rows){
           delete $rows[$inc] unless $_->{meta_number} eq $request->{meta_number};
           ++$inc;
       }
       $report->rows(\@rows);
    }

    # Business settings for 1099
    #
    my $cc = $request->{_company_config};
    $request->{company_name}      = $cc->{company_name};
    $request->{company_address}   = $cc->{company_address};
    $request->{company_telephone} = $cc->{company_phone};
    $request->{my_tax_code}       = $cc->{businessnumber};

    my $template = LedgerSMB::Template->new( # printed document
        user     => $request->{_user},
        locale   => $request->{_locale},
        path     => 'DB',
        template => $request->{taxform_name},
        format_plugin   =>
           $request->{_wire}->get( 'output_formatter' )->get( $request->{format}),
    );
    $template->render($request);

    my $body = $template->{output};
    utf8::encode($body) if utf8::is_utf8($body);  ## no critic
    my $filename = 'summary_report-' . $request->{tax_form_id} .
        '.' . lc($request->{format});
    return
        [ HTTP_OK,
          [
           'Content-Type' => $template->{mimetype},
           'Content-Disposition' => qq{attachment; filename="$filename"},
          ],
          [ $body ] ];
}

=item list_all

Lists all tax forms.

=cut

sub list_all {
    my $request= shift;
    return $request->render_report(
        LedgerSMB::Report::Taxform::List->new(%$request)
        );
}

=back

=cut

{
    local ($!, $@) = (undef, undef);
    my $do_ = 'scripts/custom/taxform.pl';
    if ( -e $do_ ) {
        unless ( do $do_ ) {
            if ($! or $@) {
                warn "\nFailed to execute $do_ ($!): $@\n";
                die (  "Status: 500 Internal server error (taxform.pm)\n\n" );
            }
        }
    }
};

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2010-2022 The LedgerSMB Core Team

This file is licensed under the GNU General Public License version 2, or at your
option any later version.  A copy of the license should have been included with
your software.

=cut


1;

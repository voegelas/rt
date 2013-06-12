jQuery(function() {
    // inputs that accept multiple email addresses
    var multipleCompletion = new Array("Requestors", "To", "Bcc", "Cc", "AdminCc", "WatcherAddressEmail[123]", "UpdateCc", "UpdateBcc");

    // inputs with only a single email address allowed
    var singleCompletion   = new Array("(Add|Delete)Requestor", "(Add|Delete)Cc", "(Add|Delete)AdminCc");

    // inputs for only privileged users
    var privilegedCompletion = new Array("AddPrincipalForRights-user");

    // build up the regexps we'll use to match
    var applyto  = new RegExp('^(' + multipleCompletion.concat(singleCompletion, privilegedCompletion).join('|') + ')$');
    var acceptsMultiple = new RegExp('^(' + multipleCompletion.join('|') + ')$');
    var onlyPrivileged = new RegExp('^(' + privilegedCompletion.join('|') + ')$');

    var inputs = document.getElementsByTagName("input");

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        var inputName = input.getAttribute("name");

        if (!inputName || !inputName.match(applyto))
            continue;

        var options = {
            source: RT.Config.WebHomePath + "/Helpers/Autocomplete/Users"
        };

        var queryargs = [];

        if (inputName.match("AddPrincipalForRights-user")) {
            queryargs.push("return=Name");
            options.select = addprincipal_onselect;
            options.change = addprincipal_onchange;
        }

        if (inputName.match(onlyPrivileged)) {
            queryargs.push("privileged=1");
        }

        if (inputName.match(acceptsMultiple)) {
            queryargs.push("delim=,");

            options.focus = function () {
                // prevent value inserted on focus
                return false;
            }

            options.select = function(event, ui) {
                var terms = this.value.split(/,\s*/);
                terms.pop();                    // remove current input
                terms.push( ui.item.value );    // add selected item
                this.value = terms.join(", ");
                return false;
            }
        }

        if (queryargs.length)
            options.source += "?" + queryargs.join("&");

        jQuery(input)
            .addClass('autocompletes-user')
            .autocomplete(options)
            .data("ui-autocomplete")
            ._renderItem = function(ul, item) {
                var rendered = jQuery("<a/>");

                if (item.html == null)
                    rendered.text( item.label );
                else
                    rendered.html( item.html );

                return jQuery("<li/>")
                    .data( "item.autocomplete", item )
                    .append( rendered )
                    .appendTo( ul );
            };
    }

    jQuery("input[data-autocomplete]:not(.ui-autocomplete-input)").each(function(){
        var input = jQuery(this);
        var what  = input.attr("data-autocomplete");
        var wants = input.attr("data-autocomplete-return");

        if (!what || !what.match(/^(Users|Groups)$/))
            return;

        input.autocomplete({
            source: RT.Config.WebPath + "/Helpers/Autocomplete/" + what
                    + (wants ? "?return=" + wants : "")
        });
    });

});

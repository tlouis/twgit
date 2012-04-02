#!/bin/bash

##
# twgit
#
# Copyright (c) 2011 Twenga SA.
#
# This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
# To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/3.0/
# or send a letter to Creative Commons, 444 Castro Street, Suite 900, Mountain View, California, 94041, USA.
#
# @copyright 2011 Twenga SA
# @copyright 2012 Geoffroy Aubry <geoffroy.aubry@free.fr>
# @license http://creativecommons.org/licenses/by-nc-sa/3.0/
#

##
# Affiche l'aide de la commande tag.
#
# @testedby TwgitHelpTest
#
function usage () {
    echo; help 'Usage:'
    help_detail '<b>twgit release <action></b>'
    echo; help 'Available actions are:'
    help_detail '<b>committers [<max>] [-F]</b>'
    help_detail '    List first <b><max></b> committers into the current release.'
    help_detail "    Default value of <b><max></b>: $TWGIT_DEFAULT_NB_COMMITTERS. Add <b>-F</b> to do not make fetch."; echo
    help_detail '<b>list [-F]</b>'
    help_detail '    List remote releases. Add <b>-F</b> to do not make fetch.'; echo
    help_detail '<b>finish [<tagname>] [-I]</b>'
    help_detail "    Merge current release branch into '$TWGIT_STABLE', create a new tag and push."
    help_detail '    If no <b><tagname></b> is specified then current release name will be used.'
    help_detail '    Add <b>-I</b> to run in non-interactive mode (always say yes).'; echo
    help_detail '<b>remove <releasename></b>'
    help_detail '    Remove both local and remote specified release branch.'
    help_detail '    Create a new tag to distinguish clearly the next release from this one.'; echo
    help_detail '<b>reset <releasename> [-I|-M|-m]</b>'
    help_detail '    Call <b>twgit remove <releasename></b>, then <b>twgit start [-I|-M|-m]</b>.'
    help_detail '    Handle options of <b>twgit start</b>.'; echo
    help_detail '<b>start [<releasename>] [-I|-M|-m]</b>'
    help_detail '    Create both a new local and remote release,'
    help_detail '    or fetch the remote release if exists on remote repository,'
    help_detail '    or checkout the local release.'
    help_detail '    Add <b>-I</b> to run in non-interactive mode (always say yes).'
    help_detail "    Prefix '$TWGIT_PREFIX_RELEASE' will be added to the specified <b><releasename></b>."
    help_detail '    If no <b><releasename></b> is specified, a name will be generated by'
    help_detail '    incrementing from last tag:'
    help_detail '        <b>-M</b> for a new major version'
    help_detail '        <b>-m</b> for a new minor version (default)'; echo
    help_detail '<b>[help]</b>'
    help_detail '    Display this help.'; echo
}

##
# Action déclenchant l'affichage de l'aide.
#
# @testedby TwgitHelpTest
#
function cmd_help () {
    usage;
}

##
# Liste les personnes ayant le plus committé sur l'éventuelle release en cours.
# Gère l'option '-F' permettant d'éviter le fetch.
#
# @param int $1 nombre de committers à afficher au maximum, optionnel
#
function cmd_committers () {
    process_options "$@"
    require_parameter '-'
    local max="$RETVAL"
    process_fetch 'F'

    local branch_fullname="$(get_current_release_in_progress)"
    [ -z "$branch_fullname" ] && die 'No release in progress!'

    display_rank_contributors "$branch_fullname" "$max"
}

##
# Liste les releases ainsi que leurs éventuelles features associées.
# Gère l'option '-F' permettant d'éviter le fetch.
#
function cmd_list () {
    process_options "$@"
    process_fetch 'F'

    local releases=$(git branch -r --merged $TWGIT_ORIGIN/$TWGIT_STABLE | grep "$TWGIT_ORIGIN/$TWGIT_PREFIX_RELEASE" | sed 's/^[* ]*//')
    if [ ! -z "$releases" ]; then
        help "Remote releases merged into '<b>$TWGIT_STABLE</b>':"
        warn "A release must be deleted after merge into '<b>$TWGIT_STABLE</b>'! Following releases should not exists!"
        display_branches 'release' "$releases"
        echo
    fi

    local release="$(get_current_release_in_progress)"
    help "Remote release NOT merged into '<b>$TWGIT_STABLE</b>':"
    if [ ! -z "$release" ]; then
        display_branches 'release' "$TWGIT_ORIGIN/$release" # | head -n -1
        info 'Features:'

        get_merged_features $release
        local merged_features="$GET_MERGED_FEATURES_RETURN_VALUE"

        local prefix="$TWGIT_ORIGIN/$TWGIT_PREFIX_FEATURE"
        for f in $merged_features; do
            echo -n "    - $f "
            echo -n $(displayMsg ok '[merged]')' '
            displayFeatureSubject "${f:${#prefix}}"
        done

        get_features merged_in_progress $release
        local merged_in_progress_features="$GET_FEATURES_RETURN_VALUE"

        for f in $merged_in_progress_features; do
            echo -n "    - $f ";
            echo -n $(displayMsg warning 'merged, then in progress.')' '
            displayFeatureSubject "${f:${#prefix}}"
        done
        [ -z "$merged_features" ] && [ -z "$merged_in_progress_features" ] && info '    - No such branch exists.'
    else
        display_branches 'release' ''
    fi
    echo

    alert_dissident_branches
}

##
# Crée une nouvelle release à partir du dernier tag.
# Si le nom n'est pas spécifié, un nom sera généré automatiquement à partir du dernier tag
# en incrémentant par défaut d'une version mineure. Ce comportement est modifiable via les
# options -M (major) ou -m (minor).
# Rappel : une version c'est major.minor.revision
# Gère l'option '-I' permettant de répondre automatiquement (mode non interactif) oui à la vérification de version.
#
# @param string $1 nom court optionnel de la nouvelle release.
#
function cmd_start () {
    process_options "$@"
    require_parameter '-'
    local release="$RETVAL"
    local release_fullname

    assert_clean_working_tree
    process_fetch
    assert_tag_exists

    local current_release=$(get_current_release_in_progress)
    current_release="${current_release:${#TWGIT_PREFIX_RELEASE}}"

    if [ -z $release ]; then
        if [ ! -z "$current_release" ]; then
            release="$current_release"
        else
            local type
            isset_option 'M' && type='major' || type='minor'
            release=$(get_next_version $type)
            echo "Release: $TWGIT_PREFIX_RELEASE$release"
            if ! isset_option 'I'; then
                echo -n $(question 'Do you want to continue? [Y/N] '); read answer
                [ "$answer" != "Y" ] && [ "$answer" != "y" ] && die 'New release aborted!'
            fi
        fi
    fi

    assert_valid_ref_name $release
    release_fullname="$TWGIT_PREFIX_RELEASE$release"

    if [ ! -z "$current_release" ]; then
        if [ "$current_release" != "$release" ]; then
            die "No more one release is authorized at the same time! Try: \"twgit release list\" or \"twgit release start $current_release\""
        else
            assert_new_local_branch $release_fullname
            exec_git_command "git checkout --track -b $release_fullname $TWGIT_ORIGIN/$release_fullname" "Could not check out release '$TWGIT_ORIGIN/$release_fullname'!"
        fi
    else
        local last_tag=$(get_last_tag)
        exec_git_command "git checkout -b $release_fullname tags/$last_tag" "Could not check out tag '$last_tag'!"
        process_first_commit 'release' "$release_fullname"
        process_push_branch $release_fullname
    fi

    alert_old_branch $TWGIT_ORIGIN/$release_fullname with-help
    echo
}

##
# Merge la release à la branche stable et crée un tag portant son nom s'il est compatible (major.minor.revision)
# ou récupère celui spécifié en paramètre.
# Gère l'option '-I' permettant de répondre automatiquement (mode non interactif) oui à la demande de pull.
#
# @param string $1 nom court de la release
# @param string $2 nom court optionnel du tag
#
function cmd_finish () {
    process_options "$@"
    require_parameter '-'
    local tag="$RETVAL"

    assert_clean_working_tree
    process_fetch

    # Récupération de la release en cours :
    processing 'Check remote release...'
    local release_fullname="$(get_current_release_in_progress)"
    [ -z "$release_fullname" ] && die 'No release in progress!'
    local release="${release_fullname:${#TWGIT_PREFIX_RELEASE}}"
    processing "Remote release '$release_fullname' detected."

    # Gestion du tag :
    [ -z "$tag" ] && tag="$release"
    local tag_fullname="$TWGIT_PREFIX_TAG$tag"
    assert_valid_tag_name $tag_fullname

    # Détection hotfixes en cours :
    processing 'Check hotfix in progress...'
    local hotfix="$(get_hotfixes_in_progress)"
    [ ! -z "$hotfix" ] && die "Close a release while hotfix in progress is forbidden! Hotfix '$hotfix' must be treated first."

    # Détection tags (via hotfixes) réalisés entre temps :
    processing 'Check tags not merged...'
    get_tags_not_merged_into_branch "$TWGIT_ORIGIN/$release_fullname"
    tags_not_merged="$(echo "$GET_TAGS_NOT_MERGED_INTO_BRANCH_RETURN_VALUE" | sed 's/ /, /g')"

    [ ! -z "$tags_not_merged" ] && die "You must merge following tag(s) into this release before close it: $tags_not_merged"

    processing 'Check remote features...'
    get_features merged_in_progress $release_fullname
    local features="$GET_FEATURES_RETURN_VALUE"

    [ ! -z "$features" ] && die "Features exists that are merged into this release but yet in development: $(echo $features | sed 's/ /, /g')!"

    processing "Check local branch '$release_fullname'..."
    if has $release_fullname $(get_local_branches); then
        assert_branches_equal "$release_fullname" "$TWGIT_ORIGIN/$release_fullname"
    else
        exec_git_command "git checkout --track -b $release_fullname $TWGIT_ORIGIN/$release_fullname" "Could not check out hotfix '$TWGIT_ORIGIN/$hotfix_fullname'!"
    fi

    exec_git_command "git checkout $TWGIT_STABLE" "Could not checkout '$TWGIT_STABLE'!"
    exec_git_command "git merge $TWGIT_ORIGIN/$TWGIT_STABLE" "Could not merge '$TWGIT_ORIGIN/$TWGIT_STABLE' into '$TWGIT_STABLE'!"
    exec_git_command "git merge --no-ff $release_fullname" "Could not merge '$release_fullname' into '$TWGIT_STABLE'!"
    create_and_push_tag "$tag_fullname" "Release finish: $release_fullname"

    # Suppression des features associées :
    get_merged_features $release_fullname
    features="$GET_MERGED_FEATURES_RETURN_VALUE"

    local prefix="$TWGIT_ORIGIN/$TWGIT_PREFIX_RELEASE"
    for feature in $features; do
        processing "Delete '$feature' feature..."
        remove_feature "${feature:${#prefix}}"
    done

    # Suppression de la branche :
    remove_local_branch $release_fullname
    remove_remote_branch $release_fullname
    echo
}

##
# Supprime la release spécifiée.
#
# @param string $1 nom court de la release
#
function cmd_remove () {
    process_options "$@"
    require_parameter 'release'
    local release="$RETVAL"
    local release_fullname="$TWGIT_PREFIX_RELEASE$release"
    local tag_fullname="$TWGIT_PREFIX_TAG$release"

    assert_valid_ref_name $release
    assert_clean_working_tree

    process_fetch
    assert_valid_tag_name $tag_fullname

    # Suppression de la branche :
    exec_git_command "git checkout $TWGIT_STABLE" "Could not checkout '$TWGIT_STABLE'!"
    exec_git_command "git merge $TWGIT_ORIGIN/$TWGIT_STABLE" "Could not merge '$TWGIT_ORIGIN/$TWGIT_STABLE' into '$TWGIT_STABLE'!"
    remove_local_branch $release_fullname
    remove_remote_branch $release_fullname

    # Gestion du tag :
    create_and_push_tag "$tag_fullname" "Release remove: $release_fullname"
    echo
}

##
# Supprime la release spécifiée et en recrée une nouvelle.
# Pour se sortir des releases non viables.
# Appelle "twgit remove <releasename>" suivi de "twgit start".
# Gère les options '-IMm' de twgit release start.
#
# @param string $1 nom court de la release à supprimer
# @testedby TwgitReleaseTest
#
function cmd_reset () {
    process_options "$@"
    require_parameter 'release'
    local release="$RETVAL"

    cmd_remove "$release" && cmd_start
}

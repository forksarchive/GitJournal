/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:launch_review/launch_review.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:time/time.dart';
import 'package:universal_io/io.dart' show Platform;

import 'package:gitjournal/analytics/analytics.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/features.dart';
import 'package:gitjournal/generated/locale_keys.g.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/repository_manager.dart';
import 'package:gitjournal/settings/app_settings.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:gitjournal/widgets/app_drawer_header.dart';
import 'package:gitjournal/widgets/pro_overlay.dart';

class AppDrawer extends StatefulWidget {
  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController animController;

  late Animation<double> sizeAnimation;
  late Animation<Offset> slideAnimation;

  @override
  void initState() {
    super.initState();

    animController =
        AnimationController(duration: 250.milliseconds, vsync: this);

    slideAnimation = Tween(begin: const Offset(0.0, -0.5), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: animController,
      curve: standardEasing,
    ));
    sizeAnimation = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: animController,
      curve: standardEasing,
    ));
  }

  @override
  void dispose() {
    animController.dispose();
    super.dispose();
  }

  Widget _buildRepoList() {
    var divider = Row(children: const <Widget>[Expanded(child: Divider())]);
    var repoManager = context.watch<RepositoryManager>();
    var repoIds = repoManager.repoIds;

    Widget w = Column(
      children: <Widget>[
        const SizedBox(height: 8),
        for (var id in repoIds) RepoTile(id),
        ProOverlay(
          feature: Feature.multiRepos,
          child: _buildDrawerTile(
            context,
            icon: Icons.add,
            title: tr(LocaleKeys.drawer_addRepo),
            onTap: () {
              var _ = repoManager.addRepoAndSwitch();
              Navigator.pop(context);
            },
            selected: false,
          ),
        ),
        divider,
      ],
    );

    w = SlideTransition(
      position: slideAnimation,
      transformHitTests: false,
      child: w,
    );

    return SizeTransition(
      sizeFactor: sizeAnimation,
      child: w,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget? setupGitButton;
    var repo = Provider.of<GitJournalRepo>(context);
    var appSettings = Provider.of<AppSettings>(context);
    var textStyle = Theme.of(context).textTheme.bodyText1;
    var currentRoute = ModalRoute.of(context)!.settings.name;

    if (!repo.remoteGitRepoConfigured) {
      setupGitButton = ListTile(
        leading: Icon(Icons.sync, color: textStyle!.color),
        title: Text(tr(LocaleKeys.drawer_setup), style: textStyle),
        trailing: const Icon(
          Icons.info,
          color: Colors.red,
        ),
        onTap: () {
          Navigator.pop(context);
          var _ = Navigator.pushNamed(context, "/setupRemoteGit");

          logEvent(Event.DrawerSetupGitHost);
        },
      );
    }

    var divider = Row(children: const <Widget>[Expanded(child: Divider())]);
    var user = Supabase.instance.client.auth.currentUser;

    return Drawer(
      child: ListView(
        // Important: Remove any padding from the ListView.
        padding: EdgeInsets.zero,
        children: <Widget>[
          AppDrawerHeader(
            repoListToggled: () {
              if (animController.isCompleted) {
                var _ = animController.reverse(from: 1.0);
              } else {
                var _ = animController.forward(from: 0.0);
              }
            },
          ),
          // If they are multiple show the current one which a tick mark
          _buildRepoList(),
          if (setupGitButton != null) ...[setupGitButton, divider],
          if (!appSettings.proMode)
            _buildDrawerTile(
              context,
              icon: Icons.power,
              title: tr(LocaleKeys.drawer_pro),
              onTap: () {
                Navigator.pop(context);
                var _ = Navigator.pushNamed(context, "/purchase");

                logEvent(
                  Event.PurchaseScreenOpen,
                  parameters: {"from": "drawer"},
                );
              },
            ),
          if (appSettings.experimentalAccounts && user == null)
            _buildDrawerTile(
              context,
              icon: Icons.account_circle,
              title: tr(LocaleKeys.drawer_login),
              onTap: () => _navTopLevel(context, '/login'),
              selected: currentRoute == '/login',
            ),
          if (!appSettings.proMode) divider,
          _buildDrawerTile(
            context,
            icon: Icons.note,
            title: tr(LocaleKeys.drawer_all),
            onTap: () => _navTopLevel(context, '/'),
            selected: currentRoute == '/',
          ),
          _buildDrawerTile(
            context,
            icon: Icons.folder,
            title: tr(LocaleKeys.drawer_folders),
            onTap: () => _navTopLevel(context, '/folders'),
            selected: currentRoute == "/folders",
          ),
          if (appSettings.experimentalGraphView)
            _buildDrawerTile(
              context,
              icon: FontAwesomeIcons.projectDiagram,
              isFontAwesome: true,
              title: tr(LocaleKeys.drawer_graph),
              onTap: () => _navTopLevel(context, '/graph'),
              selected: currentRoute == "/graph",
            ),
          if (appSettings.experimentalHistory)
            _buildDrawerTile(
              context,
              icon: Icons.history,
              isFontAwesome: true,
              title: tr(LocaleKeys.drawer_history),
              onTap: () => _navTopLevel(context, '/history'),
              selected: currentRoute == "/history",
            ),
          _buildDrawerTile(
            context,
            icon: FontAwesomeIcons.tag,
            isFontAwesome: true,
            title: tr(LocaleKeys.drawer_tags),
            onTap: () => _navTopLevel(context, '/tags'),
            selected: currentRoute == "/tags",
          ),
          divider,
          _buildDrawerTile(
            context,
            icon: Icons.share,
            title: tr(LocaleKeys.drawer_share),
            onTap: () {
              Navigator.pop(context);
              Share.share('Checkout GitJournal https://gitjournal.io/');

              logEvent(Event.DrawerShare);
            },
          ),
          if (Platform.isAndroid || Platform.isIOS)
            _buildDrawerTile(
              context,
              icon: Icons.feedback,
              title: tr(LocaleKeys.drawer_rate),
              onTap: () {
                LaunchReview.launch(
                  androidAppId: "io.gitjournal.gitjournal",
                  iOSAppId: "1466519634",
                );

                Navigator.pop(context);
                logEvent(Event.DrawerRate);
              },
            ),
          _buildDrawerTile(
            context,
            icon: Icons.rate_review,
            title: tr(LocaleKeys.drawer_feedback),
            onTap: () async {
              var platform = Platform.operatingSystem;
              var versionText = await getVersionString();
              var isPro = AppSettings.instance.proMode;

              var body =
                  "Hey!\n\nHere are some ways to improve GitJournal - \n \n\n";
              body += "Version: $versionText\n";
              body += "Platform: $platform\n";
              body += "isPro: $isPro\n";

              var exp = AppSettings.instance.proExpirationDate;
              if (exp.isNotEmpty) {
                body += "expiryDate: $exp";
              }

              final Email email = Email(
                body: body,
                subject: 'GitJournal Feedback',
                recipients: ['feedback@gitjournal.io'],
              );

              try {
                await FlutterEmailSender.send(email);
              } catch (ex, st) {
                logException(ex, st);
                showSnackbar(context, ex.toString());
              }

              Navigator.pop(context);
              logEvent(Event.DrawerFeedback);
            },
          ),
          _buildDrawerTile(
            context,
            icon: Icons.bug_report,
            title: tr(LocaleKeys.drawer_bug),
            onTap: () async {
              var platform = Platform.operatingSystem;
              var versionText = await getVersionString();
              var isPro = AppSettings.instance.proMode;

              var body = "Hey!\n\nI found a bug in GitJournal - \n \n\n";
              body += "Version: $versionText\n";
              body += "Platform: $platform\n";
              body += "isPro: $isPro\n";

              var exp = AppSettings.instance.proExpirationDate;
              if (exp.isNotEmpty) {
                body += "expiryDate: $exp";
              }

              final Email email = Email(
                body: body,
                subject: 'GitJournal Bug',
                recipients: ['bugs@gitjournal.io'],
                attachmentPaths: Log.filePathsForDates(2),
              );

              try {
                await FlutterEmailSender.send(email);
              } catch (ex, st) {
                logException(ex, st);
                showSnackbar(context, ex.toString());
              }

              Navigator.pop(context);
              logEvent(Event.DrawerBugReport);
            },
          ),
          _buildDrawerTile(
            context,
            icon: Icons.settings,
            title: tr(LocaleKeys.settings_title),
            onTap: () {
              Navigator.pop(context);
              var _ = Navigator.pushNamed(context, "/settings");

              logEvent(Event.DrawerSettings);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required void Function() onTap,
    bool isFontAwesome = false,
    bool selected = false,
  }) {
    var theme = Theme.of(context);
    var listTileTheme = ListTileTheme.of(context);
    var textStyle = theme.textTheme.bodyText1!.copyWith(
      color: selected ? theme.colorScheme.secondary : listTileTheme.textColor,
    );

    var iconW = !isFontAwesome
        ? Icon(icon, color: textStyle.color)
        : FaIcon(icon, color: textStyle.color);

    var tile = ListTile(
      leading: iconW,
      title: Text(title, style: textStyle),
      onTap: onTap,
      selected: selected,
    );
    return Container(
      child: tile,
      color: selected ? theme.selectedRowColor : theme.scaffoldBackgroundColor,
    );
  }
}

class RepoTile extends StatelessWidget {
  const RepoTile(
    this.id, {
    Key? key,
  }) : super(key: key);

  final String id;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var listTileTheme = ListTileTheme.of(context);
    var repoManager = context.watch<RepositoryManager>();

    // FIXME: Improve marking the selected repo
    var selected = repoManager.currentId == id;
    var textStyle = theme.textTheme.bodyText1!.copyWith(
      color: selected ? theme.colorScheme.secondary : listTileTheme.textColor,
    );

    var icon = FaIcon(FontAwesomeIcons.book, color: textStyle.color);

    return ListTile(
      leading: icon,
      title: Text(repoManager.repoFolderName(id)),
      onTap: () {
        repoManager.setCurrentRepo(id);
        Navigator.pop(context);
      },
    );
  }
}

void _navTopLevel(BuildContext context, String toRoute) {
  var fromRoute = ModalRoute.of(context)!.settings.name;
  Log.i("Routing from $fromRoute -> $toRoute");

  // Always first pop the AppBar
  Navigator.pop(context);

  if (fromRoute == toRoute) {
    return;
  }

  var wasParent = false;
  Navigator.popUntil(
    context,
    (route) {
      if (route.isFirst) {
        return true;
      }
      wasParent = route.settings.name == toRoute;
      if (wasParent) {
        Log.i("Router popping ${route.settings.name}");
      }
      return wasParent;
    },
  );
  if (!wasParent) {
    var _ = Navigator.pushNamed(context, toRoute);
  }
}

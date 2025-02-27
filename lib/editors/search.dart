/*
 * SPDX-FileCopyrightText: 2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:easy_localization/easy_localization.dart' as local;
import 'package:function_types/function_types.dart';

import 'package:gitjournal/generated/locale_keys.g.dart';
import 'common.dart';

class SearchInfo {
  final int numMatches;
  final double currentMatch;
  SearchInfo({this.numMatches = 0, this.currentMatch = 0});

  bool get isNotEmpty => numMatches != 0;

  static SearchInfo compute({required String body, required String? text}) {
    if (text == null) {
      return SearchInfo();
    }

    body = body.toLowerCase();
    text = text.toLowerCase();

    var matches = text.toLowerCase().allMatches(body).toList();
    return SearchInfo(numMatches: matches.length);

    // FIXME: Give the current match!!
  }
}

class EditorAppSearchBar extends StatefulWidget implements PreferredSizeWidget {
  final EditorState editorState;
  final Func0<void> onCloseSelected;

  final Func2<String, int, void> scrollToResult;

  const EditorAppSearchBar({
    Key? key,
    required this.editorState,
    required this.onCloseSelected,
    required this.scrollToResult,
  })  : preferredSize = const Size.fromHeight(kToolbarHeight),
        super(key: key);

  @override
  final Size preferredSize;

  @override
  State<EditorAppSearchBar> createState() => _EditorAppSearchBarState();
}

class _EditorAppSearchBarState extends State<EditorAppSearchBar> {
  var searchInfo = SearchInfo();
  var searchText = "";

  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();

    _focusNode = FocusNode();
    SchedulerBinding.instance?.addPostFrameCallback((Duration _) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      title: TextField(
        focusNode: _focusNode,
        style: theme.textTheme.subtitle1,
        decoration: InputDecoration(
          hintText: LocaleKeys.editors_common_find.tr(),
          border: InputBorder.none,
        ),
        maxLines: 1,
        onChanged: (String text) {
          var info = widget.editorState.search(text);
          setState(() {
            searchInfo = info;
            searchText = text;
          });

          widget.scrollToResult(searchText, searchInfo.currentMatch.round());
        },
      ),
      actions: [
        if (searchInfo.isNotEmpty)
          TextButton(
            child: Text(
              '${searchInfo.currentMatch.toInt() + 1}/${searchInfo.numMatches}',
              style: theme.textTheme.subtitle1,
            ),
            onPressed: null,
          ),
        // Disable these when not possible
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: searchInfo.isNotEmpty
              ? () {
                  setState(() {
                    var num = searchInfo.numMatches;
                    var prev = searchInfo.currentMatch;
                    prev = prev == 0 ? num - 1 : prev - 1;

                    searchInfo = SearchInfo(
                      currentMatch: prev,
                      numMatches: num,
                    );
                    widget.scrollToResult(
                        searchText, searchInfo.currentMatch.round());
                  });
                }
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward),
          onPressed: searchInfo.isNotEmpty
              ? () {
                  setState(() {
                    var num = searchInfo.numMatches;
                    var next = searchInfo.currentMatch;
                    next = next == num - 1 ? 0 : next + 1;

                    searchInfo = SearchInfo(
                      currentMatch: next,
                      numMatches: num,
                    );
                    widget.scrollToResult(
                        searchText, searchInfo.currentMatch.round());
                  });
                }
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            var _ = widget.editorState.search(null);
            widget.onCloseSelected();
          },
        ),
      ],
      // It would be awesome if the scrollbar could also change
      // like how it is done in chrome
    );
  }
}

int getSearchResultPosition(String body, String text, int pos) {
  var index = 0;
  while (true) {
    index = body.indexOf(text, index);
    pos--;
    if (pos < 0) {
      break;
    }
    index += text.length;
  }

  return index;
}

double calculateTextHeight({
  required String text,
  required TextStyle style,
  required GlobalKey editorKey,
}) {
  var renderBox = editorKey.currentContext!.findRenderObject() as RenderBox;
  var editorWidth = renderBox.size.width;

  var painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(style: style, text: text),
    maxLines: null,
  );
  painter.layout(maxWidth: editorWidth);

  var lines = painter.computeLineMetrics();
  double height = 0;
  for (var lm in lines) {
    height += lm.height;
  }
  height -= lines.last.height;

  return height;
}

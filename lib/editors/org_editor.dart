/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 * SPDX-FileCopyrightText: 2020-2021 Alen Šiljak <gitjournal@alensiljak.eu.org>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import 'package:flutter/material.dart';

import 'package:easy_localization/easy_localization.dart';

import 'package:gitjournal/core/image.dart' as core;
import 'package:gitjournal/core/md_yaml_doc_codec.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/editors/common.dart';
import 'package:gitjournal/editors/disposable_change_notifier.dart';
import 'package:gitjournal/editors/editor_scroll_view.dart';
import 'package:gitjournal/editors/undo_redo.dart';
import 'package:gitjournal/generated/locale_keys.g.dart';
import 'rich_text_controller.dart';

class OrgEditor extends StatefulWidget implements Editor {
  final Note note;
  final bool noteModified;

  @override
  final EditorCommon common;

  final bool editMode;
  final String? highlightString;
  final ThemeData theme;

  const OrgEditor({
    Key? key,
    required this.note,
    required this.noteModified,
    required this.editMode,
    required this.highlightString,
    required this.theme,
    required this.common,
  }) : super(key: key);

  @override
  OrgEditorState createState() {
    return OrgEditorState();
  }
}

class OrgEditorState extends State<OrgEditor>
    with DisposableChangeNotifier
    implements EditorState {
  late Note _note;
  late bool _noteModified;
  late TextEditingController _textController;
  late UndoRedoStack _undoRedoStack;

  final serializer = MarkdownYAMLCodec();

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _noteModified = widget.noteModified;
    _textController = buildController(
      text: serializer.encode(_note.data),
      highlightText: widget.highlightString,
      theme: widget.theme,
    );
    _undoRedoStack = UndoRedoStack();
  }

  @override
  void dispose() {
    _textController.dispose();

    super.disposeListenables();
    super.dispose();
  }

  @override
  void didUpdateWidget(OrgEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.noteModified != widget.noteModified) {
      _noteModified = widget.noteModified;
    }
  }

  @override
  Widget build(BuildContext context) {
    var editor = EditorScrollView(
      child: _NoteEditor(
        textController: _textController,
        autofocus: widget.editMode,
        onChanged: _noteTextChanged,
      ),
    );

    return EditorScaffold(
      editor: widget,
      editorState: this,
      noteModified: _noteModified,
      editMode: widget.editMode,
      parentFolder: _note.parent,
      body: editor,
      onUndoSelected: _undo,
      onRedoSelected: _redo,
      undoAllowed: _undoRedoStack.undoPossible,
      redoAllowed: _undoRedoStack.redoPossible,
    );
  }

  @override
  Note getNote() {
    _note.data = serializer.decode(_textController.text);
    return _note;
  }

  void _noteTextChanged() {
    notifyListeners();

    var editState = TextEditorState.fromValue(_textController.value);
    var redraw = _undoRedoStack.textChanged(editState);
    if (redraw) {
      setState(() {});
    }

    if (_noteModified) return;
    setState(() {
      _noteModified = true;
    });
  }

  @override
  Future<void> addImage(String filePath) async {
    var note = getNote();
    var image = await core.Image.copyIntoFs(note.parent, filePath);
    note.apply(body: note.body + image.toMarkup(note.fileFormat));

    setState(() {
      _textController.text = note.body;
      _noteModified = true;
    });
  }

  @override
  bool get noteModified => _noteModified;

  Future<void> _undo() async {
    var es = _undoRedoStack.undo();
    _textController.value = es.toValue();
    setState(() {
      // To Redraw the undo/redo button state
    });
  }

  Future<void> _redo() async {
    var es = _undoRedoStack.redo();
    _textController.value = es.toValue();
    setState(() {
      // To Redraw the undo/redo button state
    });
  }

  @override
  SearchInfo search(String? text) {
    throw UnimplementedError();
  }

  @override
  void scrollToResult(String text, int num) {
    throw UnimplementedError();
  }
}

class _NoteEditor extends StatelessWidget {
  final TextEditingController textController;
  final bool autofocus;
  final Function onChanged;

  const _NoteEditor({
    required this.textController,
    required this.autofocus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var style = theme.textTheme.subtitle1!.copyWith(fontFamily: "Roboto Mono");

    return TextField(
      autofocus: autofocus,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      style: style,
      decoration: InputDecoration(
        hintText: tr(LocaleKeys.editors_common_defaultBodyHint),
        border: InputBorder.none,
        isDense: true,
        fillColor: theme.scaffoldBackgroundColor,
        hoverColor: theme.scaffoldBackgroundColor,
        isCollapsed: true,
      ),
      controller: textController,
      textCapitalization: TextCapitalization.sentences,
      scrollPadding: const EdgeInsets.all(0.0),
      onChanged: (_) => onChanged(),
    );
  }
}

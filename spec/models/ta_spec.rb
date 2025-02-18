describe Ta do
  subject { create(:ta) }

  it { is_expected.to have_one(:grader_permission).dependent(:destroy) }
  it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:course_id) }

  describe '#percentage_grades_array' do
    let(:assignment) { create(:assignment_with_criteria_and_results) }
    let(:ta) { create(:ta) }

    context 'when the TA is not assigned any groupings' do
      it 'returns no grades' do
        expect(ta.percentage_grades_array(assignment)).to eq []
      end
    end

    context 'when the TA is assigned some groupings' do
      before do
        create(:ta_membership, role: ta, grouping: assignment.groupings.first)
        create(:ta_membership, role: ta, grouping: assignment.groupings.second)
      end

      context 'when TAs are not assigned criteria' do
        it 'returns the grades for their assigned groupings based on total marks' do
          expected = ta.groupings.where(assessment_id: assignment.id).map do |g|
            be_within(1e-4).of(g.current_result.get_total_mark / assignment.max_mark * 100)
          end

          actual = ta.percentage_grades_array(assignment)
          expect(actual).to match_array(expected)
        end
      end

      context 'when TAs are assigned specific criteria' do
        let!(:criterion1) { assignment.criteria.where(type: 'FlexibleCriterion').first }
        let!(:criterion2) { assignment.criteria.where(type: 'FlexibleCriterion').second }

        before do
          assignment.update(assign_graders_to_criteria: true)
          create(:criterion_ta_association, ta: ta, criterion: criterion1)
          create(:criterion_ta_association, ta: ta, criterion: criterion2)
        end

        it 'returns the grades for their assigned groupings based on assigned criterion marks' do
          out_of = criterion1.max_mark + criterion2.max_mark

          expected = ta.groupings.where(assessment_id: assignment.id).map do |g|
            result = g.current_result
            subtotal = (
              result.marks.find_by(criterion: criterion1).mark +
              result.marks.find_by(criterion: criterion2).mark
            )
            be_within(1e-4).of(subtotal / out_of * 100)
          end

          actual = ta.percentage_grades_array(assignment)
          expect(actual).to match_array expected
        end
      end
    end
  end

  describe '#get_num_marked_from_cache' do
    let(:instructor) { create(:instructor) }
    let(:ta) { create(:ta) }
    let(:assignment) { create(:assignment) }
    let(:grouping1) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: true) }
    let(:grouping2) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: true) }

    before do
      create(:complete_result, submission: grouping1.submissions.first)
      create(:incomplete_result, submission: grouping2.submissions.first)
      create(:ta_membership, role: ta, grouping: grouping1)
      create(:ta_membership, role: ta, grouping: grouping2)
    end

    context 'When user is a TA' do
      it 'should return the number of marked submissions for groupings associated to them' do
        expect(ta.get_num_marked_from_cache(assignment)).to eq(assignment.get_num_marked(ta.id))
      end

      context 'when they are assigned a remark request that is incomplete' do
        before do
          create(:remark_result,
                 submission: grouping1.submissions.first,
                 marking_state: Result::MARKING_STATES[:incomplete])
        end

        it 'does not count the remark request as marked' do
          expect(ta.get_num_marked_from_cache(assignment)).to eq(0)
        end
      end

      context 'when they are assigned a remark request that is complete' do
        before do
          create(:remark_result,
                 submission: grouping1.submissions.first,
                 marking_state: Result::MARKING_STATES[:complete])
        end

        it 'counts the remark request as marked' do
          expect(ta.get_num_marked_from_cache(assignment)).to eq(1)
        end
      end
    end
  end

  describe '#get_num_assigned_from_cache' do
    let(:instructor) { create(:instructor) }
    let(:ta) { create(:ta) }
    let(:ta2) { create(:ta) }
    let(:assignment) { create(:assignment) }
    let(:grouping1) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: true) }
    let(:grouping2) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: true) }
    let(:grouping3) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: true) }
    let(:grouping4) { create(:grouping_with_inviter_and_submission, assignment: assignment, is_collected: false) }

    before do
      create(:complete_result, submission: grouping1.submissions.first)
      create(:incomplete_result, submission: grouping2.submissions.first)
      create(:complete_result, submission: grouping3.submissions.first)
      create(:incomplete_result, submission: grouping4.submissions.first)
      create(:ta_membership, role: ta, grouping: grouping1)
      create(:ta_membership, role: ta, grouping: grouping2)
      create(:ta_membership, role: ta2, grouping: grouping3)
      create(:ta_membership, role: ta2, grouping: grouping4)
    end

    context 'When user is a TA' do
      it 'should return the number of submissions assigned to them' do
        expect(ta.get_num_assigned_from_cache(assignment)).to eq(assignment.get_num_assigned(ta.id))
      end

      it 'should not count submissions assigned to another ta' do
        expect(ta.get_num_assigned_from_cache(assignment)).to eq(2)
      end
    end
  end

  context 'Associated grader permission validation' do
    subject { create(:ta) }

    it { is_expected.to validate_presence_of :grader_permission }
  end

  context 'Ta model' do
    let(:user) { create(:ta) }

    it 'should create a ta' do
      expect(create(:ta)).to be_valid
    end

    it 'should create associated permissions' do
      expect(GraderPermission.exists?(user.grader_permission.id)).to be true
    end

    it 'does not allow admin users to be tas' do
      expect(build(:ta, user: create(:admin_user))).not_to be_valid
    end

    it 'does not allow autotest users to be tas' do
      expect(build(:ta, user: create(:autotest_user))).not_to be_valid
    end
  end
end

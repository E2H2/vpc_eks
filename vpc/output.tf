output "eks-vpc-id" {
    value = aws_vpc.this.id
    # eks-vpc-id라는 키 값에 aws_vpc.this.id가 들어갈 예정
    # ex) vpc-0a58a9699538b831c
}

output "pri-sub1-id" {
    value = aws_subnet.pri_sub1.id
}
output "pri-sub2-id" {
    value = aws_subnet.pri_sub2.id
}
output "pub-sub1-id" {
    value = aws_subnet.pub_sub1.id
}
output "pub-sub2-id" {
    value = aws_subnet.pub_sub2.id
}